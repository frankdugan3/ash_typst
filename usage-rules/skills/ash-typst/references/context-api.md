# AshTypst.Context and Related APIs

## Lifecycle

A context wraps a Rust-side world that keeps fonts, virtual files, and the
compiled document in memory:

1. `AshTypst.Context.new/1` — create (scans fonts, sets root)
2. `set_markup/2` — load the main Typst template
3. Inject data: `set_virtual_file/3`, `set_virtual_file_binary/3`,
   `stream_virtual_file/4`, `set_input/3`, `set_inputs/2`
4. `compile/1` — compile into a paged document
5. `render_svg/2` / `export_pdf/2` — read from the compiled document
   (`export_html/2` and `export_bundle/2` compile on their own)

Steps 2–5 repeat without recreating the context. Fonts, virtual files, and
`sys.inputs` persist until explicitly changed.

Each function acquires internal locks, so a context can be shared across
processes, but concurrent `compile`/`set_markup` on the same context serialize.

## `new/1` options

- `:root` — directory templates may read real files from. Default `nil` =
  **no filesystem access** (only virtual files and Typst packages). Sandboxed:
  paths cannot escape the root. Never point at `"."` or a directory with
  secrets.
- `:font_paths` — additional font directories to search
- `:ignore_system_fonts` — skip system fonts (default `false`)

Font scan results are cached process-wide per `{font_paths,
ignore_system_fonts}` combination — additional contexts with the same
configuration are cheap. Fonts installed later are invisible until
`AshTypst.refresh_fonts/0`.

Files on disk under `:root` are re-checked on every `compile/1`, so edits are
picked up without recreating the context. Virtual files take precedence over
disk files at the same path.

## Function reference

| Function | Notes |
| --- | --- |
| `set_markup(ctx, markup)` | Sets main template; invalidates compiled doc |
| `compile(ctx)` | `{:ok, %CompileResult{page_count, warnings}}` or `{:error, %CompileError{}}` |
| `render_svg(ctx, opts)` | Opts: `:page` (0-indexed, default 0), `:pretty` (default false), `:render_bleed` (default false) |
| `export_pdf(ctx, opts)` | Opts: `:pages` (1-indexed range string like `"1-3,5"`), `:pdf_standards` (`[:pdf_1_7 \| :pdf_a_2b \| :pdf_a_3b]`), `:document_id` |
| `export_html(ctx, opts)` | Separate compilation pass. Opts: `:pretty` |
| `export_bundle(ctx, opts)` | Separate compilation pass. Opts: `:pretty`, `:render_bleed`. Returns `{:ok, %BundleResult{files, warnings}}` |
| `set_virtual_file(ctx, path, content)` | Text content; invalidates compiled doc |
| `set_virtual_file_binary(ctx, path, content)` | Raw binary (images etc.); read in Typst via `#image(read("name", encoding: none))` |
| `append_virtual_file(ctx, path, chunk)` | Creates if new. Does **not** invalidate — call `compile/1` after streaming |
| `stream_virtual_file(ctx, path, enum, opts)` | Encodes an enumerable as a Typst array in batches. Opts: `:variable_name` (default `"data"`), `:context` (encoding context), `:batch_size` (default 100) |
| `clear_virtual_file(ctx, path)` / `clear_virtual_files(ctx)` | Invalidate compiled doc |
| `set_input(ctx, key, value)` / `set_inputs(ctx, map)` | `sys.inputs`; string keys and values only. `set_inputs` replaces all entries |
| `font_families(ctx)` | Fonts loaded in this context |

## Bundles

The `bundle` target lets one Typst project emit multiple documents and assets.
The template declares outputs with top-level `document` and `asset` elements:

```typ
#document("index.html", title: [Home])[
  = Home
  See the #link("about.html")[about page].
]
#document("about.html", title: [About])[= About]
#asset("logo.svg", read("logo.svg", encoding: none))
```

`BundleResult.files` maps relative path → rendered binary
(`%{"index.html" => "..."}`). Documents export per their declared format
(HTML, PDF, SVG, PNG); assets are emitted verbatim.

## Diagnostics

Failures return `{:error, %AshTypst.CompileError{diagnostics: [...]}}`. Each
`AshTypst.Diagnostic` has `:severity` (`:error`/`:warning`), `:message`,
`:span` (an `AshTypst.Span` with source location, or `nil`), `:trace`, and
`:hints`. Successful compiles/exports carry warnings in the result's
`warnings` list.

## AshTypst.ContextPool

Pools contexts per configuration (`root`/`font_paths`/`ignore_system_fonts`).
Render actions always use the pool; for direct usage it is opt-in:

```elixir
AshTypst.ContextPool.with_context([root: template_dir], fn ctx ->
  :ok = AshTypst.Context.set_markup(ctx, markup)

  with {:ok, _} <- AshTypst.Context.compile(ctx) do
    AshTypst.Context.render_svg(ctx, page: 0)
  end
end)
```

- Use the pool for short-lived, request-scoped rendering (preview endpoints,
  per-keystroke renders from fresh processes). Long-lived sessions holding a
  dedicated context don't need it.
- Do not use the context outside the function — it may be handed to another
  caller after return.
- Check-in scrubbing clears virtual files and `sys.inputs`, so no data leaks
  between renders. Markup is always set by the next render.
- `AshTypst.ContextPool.flush/0` drops all pooled contexts (also those
  currently checked out — dropped at check-in).
- At most `System.schedulers_online()` idle contexts are retained per
  configuration.

## Fonts

- `AshTypst.font_families/0,1` — list fonts available to Typst (no context
  needed); `AshTypst.Context.font_families/1` for a specific context.
- `AshTypst.refresh_fonts/0` — clears the process-wide font cache and flushes
  the pool so new contexts re-scan. Contexts you still hold keep their old
  fonts; recreate them to pick up changes.

## Live editing pattern

Only re-set what changed between compiles; everything else stays hot:

```elixir
:ok = AshTypst.Context.set_markup(ctx, updated_markup)
{:ok, _} = AshTypst.Context.compile(ctx)
{:ok, svg} = AshTypst.Context.render_svg(ctx, page: current_page)
```

Typst memoizes compilation process-wide — stable templates with changing data
recompile much faster than templates regenerated per render.
