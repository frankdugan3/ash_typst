# AshTypst Usage Rules

AshTypst renders [Typst](https://typst.app) documents (PDF, SVG, HTML, multi-file
bundles) from Elixir via precompiled Rust NIFs. Templates are **pure Typst**;
Elixir data crosses into them as **encoded values** — never by building Typst
source with string interpolation.

## Core rules

- **Never build Typst source with string interpolation.** No EEx, no
  `"= Invoice #{name}"`. Typst markup is code — raw interpolation is code
  injection and breaks the compile on characters like `#`, `"`, `\`, or `]`.
  Encode values with `AshTypst.Code.encode/2` and inject them as virtual files,
  or use `sys.inputs` for small string parameters.
- **Structs must opt into encoding.** Add `@derive AshTypst.Code` to any Ash
  resource (or struct) whose records will be encoded — without it, encoding
  raises `Protocol.UndefinedError`. For full control, implement the protocol
  directly: `defimpl AshTypst.Code, for: MyStruct`.
- **Templates are plain `.typ` files** kept under a root directory (default
  `"priv/typst"` for the resource extension). Keep them compilable standalone
  with the Typst CLI: `typst watch entry.typ --root priv/typst`. Ship fixture
  data in an on-disk `data.typ`; at render time the injected virtual `data.typ`
  shadows it.
- **Filesystem access is disabled by default.** A context can only read virtual
  files and Typst packages unless you pass `:root`. Everything under `:root` is
  readable by any template compiled in that context — point it at a directory
  containing only template assets, never `"."` or anywhere with secrets.
- **In Ash apps, prefer the resource extension** (`AshTypst.Resource`) over
  manual context management: render actions pool and scrub contexts
  automatically and run reads as the caller (actor, tenant, tracer, and
  `authorize?`, which defaults to `true`).

## Choosing a rendering pipeline

| Workflow | Use |
| --- | --- |
| Rendering documents from Ash resource data | `AshTypst.Resource` render actions |
| Request-scoped rendering without Ash (e.g. preview endpoint) | `AshTypst.ContextPool.with_context/2` |
| Long-lived session (editor holding state across renders) | Dedicated `AshTypst.Context`, re-set only what changed |
| Very large document whose peak memory must stay out of the VM | `AshTypst.Isolated.with_context/2` (or `isolate? true` on a render) |

## Direct context lifecycle

```elixir
{:ok, ctx} = AshTypst.Context.new(root: "/app/priv/typst")   # fonts scanned once, cached process-wide
:ok = AshTypst.Context.set_markup(ctx, markup)
:ok = AshTypst.Context.set_virtual_file(ctx, "data.typ", "#let record = #{AshTypst.Code.encode(record, %{})}\n")
:ok = AshTypst.Context.set_inputs(ctx, %{"locale" => "en"})  # strings only
{:ok, %AshTypst.CompileResult{page_count: n}} = AshTypst.Context.compile(ctx)
{:ok, svg} = AshTypst.Context.render_svg(ctx, page: 0)       # from compiled doc
{:ok, pdf} = AshTypst.Context.export_pdf(ctx, pages: "1-3", pdf_standards: [:pdf_a_2b])
{:ok, html} = AshTypst.Context.export_html(ctx)              # compiles on its own
```

- `render_svg/2` and `export_pdf/2` read the document compiled by `compile/1`;
  `export_html/2` and `export_bundle/2` perform their own compilation.
- Virtual files and `sys.inputs` **persist across compiles** until explicitly
  cleared. Clear with `clear_virtual_files/1` / `set_inputs(ctx, %{})` before
  reusing a long-lived context for a different tenant or actor.
- For large datasets use `AshTypst.Context.stream_virtual_file/4` — it encodes
  an enumerable into the virtual file in batches so Elixir memory stays flat.
- Compile failures return `{:error, %AshTypst.CompileError{diagnostics: [...]}}`
  with line/column spans and hints.

## Render actions (Ash resource extension)

```elixir
defmodule MyApp.Invoice do
  use Ash.Resource, domain: MyApp.Domain, extensions: [AshTypst.Resource]

  @derive AshTypst.Code  # required when a render action declares a `read`

  typst do
    root {:my_app, "priv/typst"}  # tuple form is release-safe

    template :invoice do
      source "invoice.typ"
    end

    render :generate_pdf do
      template :invoice
      format :pdf  # :pdf | :svg | :html | :bundle

      argument :invoice_id, :string, allow_nil?: false

      read :one do
        filter expr(id == ^arg(:invoice_id))
        load [:line_items, :customer]
      end

      pdf_options do
        pdf_standards [:pdf_a_2b]
      end
    end
  end
end

input = Ash.ActionInput.for_action(MyApp.Invoice, :generate_pdf, %{invoice_id: "123"})
{:ok, %AshTypst.Document{format: :pdf, data: pdf_binary}} = Ash.run_action(input)
```

Data is injected into a virtual `data.typ` the template imports:
`#import "data.typ": record, args`. Available bindings: `args` always; `record`
with `read :one`; `records` (an array) with `read :many`.

- `filter`, `load`, `sort` and `arguments` in a `read` accept Ash templates:
  `^arg(:name)`, `^actor(:field)`, `^tenant()`, `^context(:key)` inside
  `expr/1`, and the same without `^` outside it
  (`load label: %{prefix: arg(:prefix)}`). `select` and `limit` are static.
  An `arg` that names an undeclared argument is a compile error.
- `read` uses the primary read action; set `action` (and `arguments`) to run
  another one.
- `read :many` **requires `stream_with`** — there is no default.
  `:keyset`/`:offset` stream page by page with `Ash.stream!/2` and need that
  pagination on the read action (default `:read` actions have both; for a
  custom action add `pagination keyset?: true, required?: false`). `:none`
  reads every record in one unpaginated read. Compile-time checked against
  the action. Prefer `:keyset` for large results.
- Typst needs ~100× the data file size in memory to lay out a document. A
  streamed render evicts Typst's VM-wide memoization cache when it ends
  (success, error or raise) and returns the memory to the OS; the next
  render starts with a cold cache. Fonts, templates and assets are kept.
- `isolate? true` on a render runs Typst in a throwaway OS process
  (`AshTypst.Isolated`), so the peak never lands in the VM, and streams the
  records from a task. The read then runs outside the caller's process:
  `private? true` ETS tables look empty, and `transaction? true` with a
  streamed read is a compile error.
- Set `encoding_context` on the render to pass an encoding context, e.g.
  `encoding_context %{timezone: arg(:timezone)}`.

## Encoding semantics (built-in Ash resource implementation)

- Only `public?: true` fields are considered; private fields never reach templates.
- **Not selected / not loaded = absent** from the encoded dictionary (not
  `none`). Loaded-but-empty encodes as `none`. Forbidden fields
  (`Ash.ForbiddenField`) are silently omitted.
- Templates shared by actions with different loads should read varying fields
  with `record.at("field", default: none)`.
- Encoded output is Typst source the compiler parses on every compile — use
  `select` in the `read` block to drop columns the template doesn't use,
  especially for `:many` renders.
- Dictionary key order is not stable across VM runs; access fields by name.
- Dates/times encode as Typst `datetime(...)`. Pass `%{timezone: "..."}` in the
  encoding context to shift zones (requires a configured time-zone database);
  in a render action, set it with `encoding_context`.
- `sensitive? true` on attributes/arguments redacts telemetry only — it does
  **not** keep values out of rendered documents. Use `public?: false`,
  de-select, `struct_keys`, or a custom `defimpl` for that.

## Fonts

- Font scans are cached process-wide per configuration; call
  `AshTypst.refresh_fonts/0` after installing fonts (it also flushes the
  context pool).
- Ship fonts with your app for reproducible output (e.g. CJK):
  `font_paths [{:my_app, "priv/fonts"}]`.

## Releases

Use `{otp_app, subpath}` tuples for `root` and `font_paths` in the `typst` DSL
section — resolved via `Application.app_dir/2` at runtime, so they work in dev,
test, and Mix releases. Plain relative strings only work when cwd is the
project root.
