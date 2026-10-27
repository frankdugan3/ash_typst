defmodule AshTypst do
  @moduledoc """
  Precompiled Rust NIFs for rendering [Typst](https://typst.app) documents from Elixir.

  All rendering goes through a persistent `AshTypst.Context`, which shares the
  process-wide font cache and keeps the compiled document in memory so you can
  render pages, export PDFs, or re-compile after a markup change without
  repeating expensive setup.

  ## Architecture

  ```mermaid
  graph TB
    subgraph "Peer VM -- exits after the render"
      PN["Own context, NIF<br/>and caches"]
    end

    subgraph "Your VM"
      R["Render action<br/>AshTypst.Resource"]
      I[AshTypst.Isolated]
      P[AshTypst.ContextPool]
      C[AshTypst.Code]
      A[AshTypst.Context]
      N[AshTypst.NIF]
    end

    subgraph "Shared by all contexts"
      FC["Font cache<br/>refresh_fonts/0"]
      MC["Memoization cache<br/>evict_cache/1"]
    end

    subgraph "TypstContext -- one per context"
      W["SystemWorld<br/>markup, virtual files,<br/>sys.inputs, files from root"]
      PD[PagedDocument]
    end

    subgraph "Outputs"
      HTML["HTML<br/>export_html/2"]
      BUN["Bundle<br/>export_bundle/2"]
      SVG["SVG<br/>render_svg/2"]
      PDF["PDF<br/>export_pdf/2"]
    end

    R -->|"isolate? true"| I
    R -->|default| P
    I -->|stdio| PN
    P --> A
    C -->|encode| A
    A --> N
    N --> W
    FC -.->|fonts| W
    MC -.->|reused| W
    W -->|compile/1| PD
    W --->|compiles itself| HTML
    W ---> BUN
    PD --> SVG
    PD --> PDF
  ```

  **Key points:**

  - The `TypstContext` is a Rust NIF resource held as an opaque reference in Elixir.
  - Font scans are cached process-wide per font configuration and shared by every
    context; `refresh_fonts/0` clears the cache.
  - `compile/1` stores a `PagedDocument`; `render_svg/2` and `export_pdf/2` read
    from it without recompiling. `export_html/2` and `export_bundle/2` compile on
    their own (they use different document types internally).
  - Virtual files and `sys.inputs` persist across compiles until explicitly
    changed. `AshTypst.ContextPool` clears them, and the compiled document, when a
    context is returned.
  - Typst memoizes evaluation and layout in a cache shared by the whole VM. Each
    compile drops entries unused for 10 compiles; `evict_cache/1` evicts more and
    returns the memory to the OS, and render actions call it after every streamed
    `read :many`.
  - Render actions use `AshTypst.ContextPool`, or, with `isolate? true`,
    `AshTypst.Isolated`, which runs the context in a peer VM that exits after the
    render. See the [Large documents](large-documents.md) guide.

  ## Quick start

      # Create a context (fonts scanned once)
      {:ok, ctx} = AshTypst.Context.new(root: "/path/to/templates")

      # Set markup and compile
      :ok = AshTypst.Context.set_markup(ctx, "= Hello World")
      {:ok, %AshTypst.CompileResult{page_count: 1}} = AshTypst.Context.compile(ctx)

      # Render any page as SVG
      {:ok, svg} = AshTypst.Context.render_svg(ctx, page: 0)

      # Export the full document as PDF
      {:ok, pdf_binary} = AshTypst.Context.export_pdf(ctx)

  ## Data injection

  You can feed Elixir data into templates in two ways:

  ### Virtual files

  Create in-memory `.typ` files that your template can `#import`:

      AshTypst.Context.set_virtual_file(ctx, "data.typ", ~s(#let title = "Q4 Report"))
      AshTypst.Context.set_markup(ctx, ~s(#import "data.typ": title\\n= \\#title))

  For large datasets, stream records in batches to keep Elixir memory flat:

      AshTypst.Context.stream_virtual_file(ctx, "rows.typ", records_stream,
        variable_name: "rows",
        context: %{timezone: "America/New_York"}
      )

  ### `sys.inputs`

  Pass simple string key/value pairs accessible via `#sys.inputs` in templates:

      AshTypst.Context.set_inputs(ctx, %{"theme" => "dark", "locale" => "en"})

  ## Data encoding

  The `AshTypst.Code` protocol converts Elixir values to Typst source syntax.
  It handles maps, lists, dates, decimals, Ash resources, and more.
  See `AshTypst.Code.encode/2` for the full type mapping.

  ## Live editing

  The context is designed for iterative workflows. Only the markup (or virtual
  file) that changed needs to be re-set before re-compiling; fonts and other
  state stay hot:

      :ok = AshTypst.Context.set_markup(ctx, updated_template)
      {:ok, _} = AshTypst.Context.compile(ctx)
      {:ok, svg} = AshTypst.Context.render_svg(ctx, page: current_page)
  """

  alias AshTypst.ContextPool
  alias AshTypst.NIF

  @doc """
  List all font families available to Typst.

  This is a standalone operation that does not require a context.
  For fonts loaded in a context, use `AshTypst.Context.font_families/1`.
  """

  def font_families(%AshTypst.FontOptions{} = opts \\ %AshTypst.FontOptions{}) do
    NIF.font_families(opts)
  end

  @doc """
  Refresh font discovery after fonts are installed or removed.

  Font scan results are cached process-wide (per font configuration) and
  reused by every new context, so font changes on the system are not
  visible automatically. Calling this clears that cache and drops all
  pooled render contexts — new contexts and render actions then re-scan.

  Contexts you are still holding keep the fonts they were created with;
  recreate them to pick up the changes.
  """
  def refresh_fonts do
    :ok = NIF.clear_font_cache()
    ContextPool.flush()
  end

  @doc """
  Evict Typst's memoization cache and return the freed memory to the OS.

  Typst memoizes evaluation and layout in a cache that is shared by every
  context in the VM. Each compile already evicts entries that went unused
  for 10 compiles; this evicts entries unused for `max_age` evictions,
  where `0` (the default) evicts everything. On glibc systems the freed
  memory is then trimmed with `malloc_trim`, without which it stays
  resident.

  Render actions call this after every streamed `read :many` render (see
  `AshTypst.Resource.Render.Read`). Call it yourself after other large or
  one-off renders, for example at the end of a background export job:
  distinct large documents (each with its own id or timestamp) never hit
  the cache again, yet stay resident until 10 more compiles age them out.
  This releases memory between renders; it does not lower the peak of a
  single render (see `AshTypst.Isolated` for that).

  The cache is process-wide, so a full eviction also discards entries that
  other renders could have reused: the next compile of any template starts
  cold (template evaluation, text shaping plans, decoded images). Fonts,
  template files and virtual files are not part of this cache and are kept.

  Emits the `[:ash_typst, :cache, :evict]` telemetry event with the
  `:duration` (native time units) as measurement and `:max_age` as
  metadata.
  """
  def evict_cache(max_age \\ 0) when is_integer(max_age) and max_age >= 0 do
    start = System.monotonic_time()
    :ok = NIF.evict_cache(max_age)

    :telemetry.execute(
      [:ash_typst, :cache, :evict],
      %{duration: System.monotonic_time() - start},
      %{max_age: max_age}
    )
  end
end
