# Large documents

A document with a few pages renders in milliseconds and a few megabytes, and
none of this guide matters for it. A document with tens of thousands of
records and thousands of pages is different: it can take minutes and many
gigabytes of memory, and how that memory is used and released decides
whether your server stays up. This guide explains where the memory goes, what
AshTypst does about it by default, and the options you have, with their
trade-offs.

## The short version

- Render records from Ash with a render action and `read :many` with
  `stream_with :keyset`. It streams the records, and it releases Typst's
  memory when the render ends.
- `select` only what the template uses.
- If one render's peak memory may not fit next to the rest of your
  application, set `isolate? true` on the render action. Typst then runs in a
  separate OS process that exits afterwards.
- Plan capacity by peak memory × concurrent large renders, and limit that
  concurrency (for example with a dedicated Oban queue).

## Where the memory goes

Typst's memory use is driven by what it lays out, not by the size of the data
you hand it. The data file is parsed into a syntax tree, evaluated into Typst
values, and then laid out into pages. Every rendered character becomes a
positioned glyph of about 56 bytes, every run of text keeps its own copy of
the text, and every paragraph, block and page is laid out by a memoized
function whose result Typst keeps in a cache.

Measured with a simple listing template (a few text fields per record, one
block per record), per byte of the data file:

| Phase                | Memory                                            | Lifetime                    |
| -------------------- | ------------------------------------------------- | --------------------------- |
| The data file itself | about 2× (the encoded chunks and the file buffer) | until the render ends       |
| Parsing              | about 14×                                         | freed when the compile ends |
| Evaluated records    | about 7×                                          | kept in Typst's cache       |
| Laid-out pages       | about 100×                                        | kept in Typst's cache       |
| PDF export           | a few hundred MB on top                           | freed when the export ends  |

So a 14 MB data file (50,000 records, 2,942 pages) peaked at 1.5 GB, a 60 MB
file (200,000 records, 11,765 pages) at 5.7 GB, and a real-world 180 MB file
for a book of about 12,800 pages, with a much richer template, at about
30 GB. Your ratio depends on your template: more text per record, tables,
and nested layout cost more; fields that are encoded but never shown cost
only parsing and evaluation.

Two more things affect the peak:

- **Relayout passes.** When a template uses introspection (page counters
  such as "page 3 of 120", `context`, `query`, outlines), Typst lays the
  document out again until the results settle, up to five times. Pages that
  didn't change are reused from the cache, so a page-counter footer added
  only about 10% in our measurements, but templates whose content changes
  between passes pay more.
- **The previous render.** Memory left behind by an earlier render (see
  below) adds to the next render's peak.

## The memory lifecycle

| What                                                        | Where it lives                                    | When it is freed                                    |
| ----------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- |
| Font scan and loaded font data                              | process-wide font cache                           | `AshTypst.refresh_fonts/0`                          |
| Contexts of render actions                                  | `AshTypst.ContextPool`, one per scheduler at most | when the pool is flushed                            |
| Template markup, template files and assets read from `root` | the context                                       | replaced by the next render                         |
| Virtual files (`data.typ`) and `sys.inputs`                 | the context                                       | when the context returns to the pool                |
| The compiled document                                       | the context                                       | when the context returns to the pool                |
| Evaluation and layout results                               | Typst's memoization cache, shared by the whole VM | eviction                                            |
| Freed memory                                                | the memory allocator                              | `malloc_trim` (glibc) or the allocator's own policy |

The last two rows are the ones that matter for large documents.

**Typst's memoization cache** is what makes re-rendering a changed document
fast: unchanged parts are reused. It is shared by every context in the VM,
and each compile drops entries that went unused for ten compiles. So after a
large render, its layouts stay in memory until ten more compiles have
happened anywhere in the VM, which in a service that renders a big document
now and then can be indefinitely. Dropping the compiled document does not
help on its own, because the document's pages are shared with the cache.

**The memory allocator** keeps freed memory for reuse instead of returning
it to the operating system. On Linux with glibc that means a large render's
memory stays resident even after Typst has freed it, unless it is trimmed.

## Streaming the data

A `read :many` must choose how its records are fetched with `stream_with`;
there is no default, so the choice is always visible:

- `stream_with :keyset` (preferred) or `:offset` streams the records with
  `Ash.stream!/2`: it fetches one page of `batch_size` records, encodes it,
  appends it to the data file and only then fetches the next page. Only one
  page of records is in Elixir memory at a time, whatever the size of the
  result. The read action must support that pagination.
- `stream_with :none` reads every record in one go. Fine for small results;
  for a large document, every record and its encoding are in memory at
  once, and the render does not evict Typst's cache afterwards.

See `AshTypst.Resource.Render.Read` for the details.

Before streaming, the render compiles the template against the first page of
records (the preflight), so a template error is reported in seconds instead
of after every record was fetched. See the Preflight section of
`AshTypst.Resource.Render.Read`.

Outside render actions, `AshTypst.Context.stream_virtual_file/4` does the
same for any enumerable.

Streaming keeps the Elixir side flat. It does nothing about Typst's own
memory, which is the large part.

## Making the document cheaper

The cheapest memory is the memory Typst never needs:

- **`select` only what the template reads.** Every encoded field is parsed
  and evaluated for every record. Loads and calculations are encoded too.
- **Aggregate in the query.** Sums and counts your data layer computes (Ash
  aggregates) cost nothing in Typst; the same in template code iterates the
  whole array.
- **Keep introspection out of the per-record path.** A counter in the page
  footer is cheap; queries or `context` blocks inside every record make
  relayout passes expensive.
- **Split very large outputs** when the use case allows it, for example one
  document per month or per location, rendered one after another. Each render
  then peaks at a fraction of the whole.

## Releasing memory after a render

### Automatic eviction after streamed renders

A render action whose `read :many` is streamed evicts Typst's whole
memoization cache when it ends, whether it succeeded, failed or raised, and
then returns the freed memory to the operating system. A streamed render
re-fetches its records every time, so nothing it cached could be reused.

The trade-off is that the cache is shared: the next render of any template
in the VM starts cold, and template evaluation, text shaping plans and
decoded images are computed again. That costs milliseconds, not seconds.
Fonts, template files and assets are not part of the cache and stay loaded.

Renders with `stream_with :none`, a `:one` read or no read keep the cache as
before; they are rarely large, and they benefit from it.

### Evicting yourself

After a large render through `AshTypst.Context`, or any render you know will
not be repeated (a background export with its own ids and timestamps), call
`AshTypst.evict_cache/0`. `AshTypst.evict_cache/1` takes a maximum age
instead, to keep entries used in the last few compiles. Both emit the
`[:ash_typst, :cache, :evict]` telemetry event.

### What eviction does not do

- **It does not lower the peak.** The memory is released after the render;
  while it runs, the render needs all of it.
- **It cannot return everything.** On Linux with glibc, eviction is followed
  by `malloc_trim`, which in our measurements returned about 95% (from 5.7 GB
  at the peak back to 0.3 GB above the starting point). Memory that is still
  in use, or freed in small pieces scattered between allocations that are,
  stays resident, and is reused by the next render. On other platforms the
  allocator decides when to return memory.

## Isolating a render

For the largest documents, take Typst out of your VM altogether. Set
`isolate? true` on the render action:

```elixir
render :annual_report do
  template :annual_report
  format :pdf
  isolate? true

  read :many do
    select [:id, :name, :total]
    stream_with :keyset
    batch_size 2500
  end
end
```

or use `AshTypst.Isolated.with_context/2` directly, whose context works with
every `AshTypst.Context` function:

```elixir
AshTypst.Isolated.with_context([root: template_dir], fn ctx ->
  :ok = AshTypst.Context.set_markup(ctx, markup)
  :ok = AshTypst.Context.stream_virtual_file(ctx, "data.typ", records, variable_name: "records")

  with {:ok, _} <- AshTypst.Context.compile(ctx) do
    AshTypst.Context.export_pdf(ctx)
  end
end)
```

### How it works

- A peer node (a second Erlang VM, started with `:peer`) is started for the
  render. It loads the same code and the same NIF, creates the context and
  runs every compile and export. It talks to your VM over its standard I/O,
  so Erlang distribution is not needed.
- Your VM still reads and encodes the records. In a render action, the
  streamed read runs in a `Task` that exits when the data file is written,
  so the memory used to fetch and encode the records is freed with it,
  instead of staying in the heap of a long-lived caller such as an Oban
  worker or a GenServer.
- Data chunks and the exported document (anything over 64 KB) travel through
  files in a private directory (mode `0700`) under `System.tmp_dir!/0`,
  because the standard I/O connection is slow for large binaries. The
  directory is removed afterwards.
- When the render ends, the peer exits and the operating system takes back
  every byte it used: nothing is left in your VM, and nothing for the
  allocator to hold on to.

### What it buys you

- **Nothing stays resident.** In a real-world test of the 30 GB book above,
  the isolated render left nothing.
- **Running out of memory fails the render, not the server.** When the
  machine runs out of memory, the kernel's OOM killer picks the largest
  process, which is the peer. The render then fails with
  `AshTypst.Isolated.Error` (a render action returns it as an error) and
  your VM carries on.
- **The same speed.** Starting the peer and scanning fonts takes a fraction
  of a second; the rendering itself is just as fast. The 30 GB book took
  210 s isolated against 212–219 s in the VM.

### What it costs

- **No caching between renders.** Each render starts a peer and scans fonts.
  Fine for a report that takes seconds to minutes; wasteful for small
  documents rendered often, such as per-request previews. Use
  `AshTypst.ContextPool` for those.
- **The read runs in another process.** Data that is scoped to the calling
  process is not visible to it: a `private? true` ETS table looks empty.
  For the same reason it can't take part in the render's transaction, so
  `isolate? true` together with `transaction? true` and a streamed read is a
  compile error. Records read with `stream_with :none` or `read :one` are
  still read in the caller.
- **Rendered data touches the disk**, in the private spool directory, for
  the duration of the render.

### Requirements

The peer is started with the `erl` executable of the running installation
(found under `:code.root_dir/0`), so it works in development and in a Mix
release that includes ERTS (the default). It gets the code paths of your VM;
your application is not started in it, and doesn't need to be.

## Choosing an approach

| Situation                                                                     | Approach                                             |
| ----------------------------------------------------------------------------- | ---------------------------------------------------- |
| Small and medium documents, any frequency                                     | defaults; nothing to do                              |
| Previews and other frequent small renders                                     | `AshTypst.ContextPool.with_context/2`                |
| Large documents rendered now and then, peak fits comfortably next to your app | `read :many` render action with `stream_with :keyset` (automatic eviction)      |
| Large document rendered directly through `AshTypst.Context`                   | call `AshTypst.evict_cache/0` afterwards             |
| Peak close to the memory available, or memory must not stay resident          | `isolate? true` / `AshTypst.Isolated.with_context/2` |
| Several such documents at once                                                | isolation, and limit their concurrency               |

## Capacity planning

Isolation and eviction both deal with what happens after a render. Neither
makes a single render smaller, so the machine has to fit the peak of every
large render that runs at the same time, plus the rest of your application:

- Measure the peak of your largest real document (see below), not a sample:
  memory grows with the number of pages.
- Run large renders from a job queue with a small, fixed concurrency, for
  example a dedicated Oban queue with `limit: 1`. Two 30 GB renders in a
  queue that allows two jobs need 60 GB.
- Without isolation, add what the previous render may have left resident to
  the next render's peak.

## Measuring

- **The VM:** `VmRSS` (current) and `VmHWM` (peak) in `/proc/self/status` on
  Linux, read before and after a render. `:erlang.memory(:total)` shows the
  BEAM's own memory; the difference to RSS is native memory, almost all of
  it Typst's.
- **An isolated render:** the peer is a separate OS process; inside
  `AshTypst.Isolated.with_context/2`, `:peer.call(ctx.peer, :os, :getpid,
[])` gives its OS pid, whose `/proc/<pid>/status` has its peak.
- **Eviction:** attach to the `[:ash_typst, :cache, :evict]` telemetry event
  to see when the cache is evicted and how long it took.
