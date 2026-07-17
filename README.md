[![hex.pm](https://img.shields.io/hexpm/l/ash_typst.svg)](https://hex.pm/packages/ash_typst)
[![hex.pm](https://img.shields.io/hexpm/v/ash_typst.svg)](https://hex.pm/packages/ash_typst)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/ash_typst)
[![hex.pm](https://img.shields.io/hexpm/dt/ash_typst.svg)](https://hex.pm/packages/ash_typst)
[![github.com](https://img.shields.io/github/last-commit/frankdugan3/ash_typst.svg)](https://github.com/frankdugan3/ash_typst)

# AshTypst

Precompiled Rust NIFs for rendering [Typst templates](https://typst.app) via an extensible data-encoding protocol with built-in Ash support. Compile markup to SVG, PDF, or HTML with persistent contexts that keep
fonts and compiled state in memory for fast, iterative rendering.

## Features

- **Persistent context** — font scans are cached process-wide and reused across contexts and compiles; call `AshTypst.refresh_fonts/0` to pick up newly installed fonts
- **Multi-page rendering** — compile once, render any page as SVG
- **PDF export** — proper binary output with page ranges, PDF/A standards, and document IDs
- **HTML export** — via `typst-html`
- **Virtual files** — inject data as in-memory `.typ` files your templates can `#import`
- **Sandboxed filesystem access** — opt in to reading templates and assets from a root directory; disabled by default
- **Streaming** — feed large datasets from Elixir streams into virtual files in constant memory
- **`sys.inputs`** — pass simple string parameters accessible via `#sys.inputs` in templates
- **Rich diagnostics** — compile errors include line/column numbers
- **Data encoding** — the `AshTypst.Code` protocol converts Elixir types (maps, lists, dates, decimals, Ash resources) to Typst syntax
- **Timezone-aware encoding** — dates and times are automatically shifted to a configured timezone when encoding to Typst
- **Ash Resource Extension** - define template-rendering actions inside your resources via DSL

## Installation

Add `ash_typst` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_typst, "~> 0.3"}
  ]
end
```

Precompiled NIF binaries are downloaded automatically for common targets. To
compile from source, add `{:rustler, "~> 0.35"}` as an optional dependency and
set `RUSTLER_PRECOMPILATION_EXAMPLE_FORCE_BUILD=1`.

## Quick start

```elixir
# 1. Create a context — fonts loaded once, reused for all operations.
#    `root:` is optional; see "Filesystem access" below.
{:ok, ctx} = AshTypst.Context.new(root: "/path/to/templates")

# 2. Set the main template
:ok = AshTypst.Context.set_markup(ctx, """
  #import "data.typ": records
  = Invoice \#sys.inputs.at("invoice_id")
  #for r in records [- \#r.name: \#r.amount]
""")

# 3. Inject data
AshTypst.Context.set_inputs(ctx, %{"invoice_id" => "INV-42"})
AshTypst.Context.stream_virtual_file(ctx, "data.typ", line_items,
  variable_name: "records"
)

# 4. Compile
{:ok, %AshTypst.CompileResult{page_count: n}} = AshTypst.Context.compile(ctx)

# 5. Render
{:ok, svg}        = AshTypst.Context.render_svg(ctx, page: 0)
{:ok, pdf_binary} = AshTypst.Context.export_pdf(ctx, pages: "1-3", pdf_standards: [:pdf_a_2b])
{:ok, html}       = AshTypst.Context.export_html(ctx)
```

## Context API

All rendering is done through `AshTypst.Context`.

| Function                | Purpose                                                |
| ----------------------- | ------------------------------------------------------ |
| `new/1`                 | Create a context with root path and font options       |
| `set_markup/2`          | Set the main Typst template (invalidates compiled doc) |
| `compile/1`             | Compile markup into a paged document                   |
| `render_svg/2`          | Render a page as SVG                                   |
| `export_pdf/2`          | Export the document as a PDF binary                    |
| `export_html/1`         | Export as HTML (separate compilation pass)             |
| `set_virtual_file/3`    | Set an in-memory file importable by templates          |
| `stream_virtual_file/4` | Stream an enumerable into a virtual file               |
| `append_virtual_file/3` | Append a chunk to a virtual file                       |
| `clear_virtual_file/2`  | Remove a virtual file                                  |
| `clear_virtual_files/1` | Remove all virtual files                               |
| `set_input/3`           | Set a single `sys.inputs` entry                        |
| `set_inputs/2`          | Replace all `sys.inputs` entries                       |
| `font_families/1`       | List fonts loaded in this context                      |

## Filesystem access

By default a context has **no filesystem access**: templates can only reference
virtual files and Typst packages, and any other file reference fails to compile.

To let templates read real files from disk — `#import`ed templates, images,
data files — pass the `:root` option:

```elixir
{:ok, ctx} = AshTypst.Context.new(root: "/app/priv/typst")

:ok = AshTypst.Context.set_markup(ctx, """
#import "templates/invoice.typ": invoice  // read from /app/priv/typst/templates/
#image("assets/logo.png")                 // read from /app/priv/typst/assets/
""")
```

The root behaves like the Typst CLI's `--root`: all paths resolve inside it and
cannot escape it (e.g. via `..`). Files on disk are re-checked on every
`compile/1`, so edits are picked up without recreating the context. Virtual
files take precedence over disk files at the same path.

> [!WARNING]
> Everything under `:root` becomes readable by any template compiled in the
> context. Point it at a directory containing only template assets — never at
> `"."` or another directory that may hold secrets (`.env`, config files, etc.).

For Mix releases, prefer an absolute path derived at runtime, e.g.
`Application.app_dir(:my_app, "priv/typst")`. The Ash resource extension does
this for you via `root {:my_app, "priv/typst"}`.

## Data encoding

The `AshTypst.Code` protocol converts Elixir values into Typst source syntax:

| Elixir type                                    | Typst type                    |
| ---------------------------------------------- | ----------------------------- |
| `Map`                                          | `dictionary`                  |
| `List`                                         | `array`                       |
| `Integer`                                      | `int(n)`                      |
| `Float`                                        | `float(n)`                    |
| `Decimal`                                      | `decimal(n)`                  |
| `String`                                       | `"str"`                       |
| `DateTime` / `NaiveDateTime` / `Date` / `Time` | `datetime(...)`               |
| `true` / `false`                               | `true` / `false`              |
| `nil`                                          | `none`                        |
| Ash resource                                   | `dictionary` of public fields |

To encode an Ash resource's records (or any struct) you must opt it into the
protocol by adding `@derive AshTypst.Code` to the module. Deriving uses the
built-in implementation, which serializes a resource's public fields. For full
control over how a struct serializes, implement the protocol directly with
`defimpl AshTypst.Code, for: MyStruct`.

## Ash Resource Extension

`AshTypst.Resource` is a Spark DSL extension that lets you declare Typst templates
and render actions directly on your Ash resources. Each render action becomes a
standard Ash generic action that returns an `AshTypst.Document` struct.

```elixir
defmodule MyApp.Invoice do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypst.Resource]

  # Opt this resource into the encoding protocol so `read` results can be
  # serialized to Typst and injected into your templates.
  @derive AshTypst.Code

  typst do
    root "priv/typst"

    template :invoice do
      source "invoice.typ"
      inputs %{"company" => "Acme Corp"}
    end

    template :receipt do
      # ~TYPST sigil is auto-imported inside template blocks
      markup ~TYPST"""
      #import "data.typ": record, args
      = Receipt \#args.receipt_number
      *Customer:* \#record.name
      """
    end

    render :generate_pdf do
      template :invoice
      format :pdf

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
```

Call the action like any other Ash generic action:

```elixir
input = Ash.ActionInput.for_action(MyApp.Invoice, :generate_pdf, %{invoice_id: "123"})
{:ok, %AshTypst.Document{format: :pdf, data: pdf_binary}} = Ash.run_action(input)
```

Data is injected into a virtual file (`data.typ` by default) that your template can
`#import`. Depending on the read cardinality, your template receives `record` (single),
`records` (list), and/or `args` (action arguments).

For the complete DSL reference, see the
[AshTypst.Resource DSL cheatsheet](https://hexdocs.pm/ash_typst/dsl-ashtypst-resource.html).

## Live editing

The context is designed for iterative workflows. After the initial setup, only
the changed markup or data needs to be re-set before re-compiling:

```elixir
# Initial render
:ok = AshTypst.Context.set_markup(ctx, template_v1)
{:ok, _} = AshTypst.Context.compile(ctx)
{:ok, svg} = AshTypst.Context.render_svg(ctx)

# User edits template — only re-set what changed
:ok = AshTypst.Context.set_markup(ctx, template_v2)
{:ok, _} = AshTypst.Context.compile(ctx)
{:ok, svg} = AshTypst.Context.render_svg(ctx)
```

Fonts, virtual files, and `sys.inputs` all persist across re-compilations.

## Context pooling

Ash render actions automatically reuse contexts through `AshTypst.ContextPool`.
For direct `AshTypst.Context` usage the pool is opt-in: wrap renders in
`with_context/2` instead of creating a context per render. This is ideal for
request-scoped rendering — for example a real-time preview editor where every
keystroke triggers a render from a fresh process:

```elixir
def handle_event("edit", %{"markup" => markup}, socket) do
  {:ok, svg} =
    AshTypst.ContextPool.with_context([root: template_dir()], fn ctx ->
      :ok = AshTypst.Context.set_markup(ctx, markup)

      with {:ok, _} <- AshTypst.Context.compile(ctx) do
        AshTypst.Context.render_svg(ctx, page: 0)
      end
    end)

  {:noreply, assign(socket, :preview, svg)}
end
```

Contexts are pooled per option set and handed back cleaned (virtual files and
`sys.inputs` cleared), so nothing leaks between renders. Long-lived sessions
that keep a dedicated context (the "Live editing" pattern above) don't need the
pool — it pays off when the rendering process is short-lived.
