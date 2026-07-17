# AshTypst.Resource DSL

Spark DSL extension adding a `typst` section to Ash resources. Each `render`
entity becomes a standard Ash generic action returning an `AshTypst.Document`.

## Full example

```elixir
defmodule MyApp.Invoice do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [AshTypst.Resource]

  # Required whenever a render action declares a `read` — records are encoded
  # via the AshTypst.Code protocol. Validated at compile time.
  @derive AshTypst.Code

  typst do
    root {:my_app, "priv/typst"}          # default "priv/typst"
    font_paths [{:my_app, "priv/fonts"}]  # default []
    ignore_system_fonts false             # default false

    template :invoice do
      source "invoice.typ"                # file relative to root
      inputs %{"company" => "Acme Corp"}  # static sys.inputs (strings)
    end

    template :receipt do
      # ~TYPST sigil is auto-imported inside template blocks; it is a raw
      # sigil (no interpolation/escaping), so `#` passes through literally.
      markup ~TYPST"""
      #import "data.typ": record, args
      = Receipt #args.receipt_number
      *Customer:* #record.name
      """
    end

    render :generate_pdf do
      template :invoice
      format :pdf                          # :pdf | :svg | :html | :bundle

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

Calling:

```elixir
input = Ash.ActionInput.for_action(MyApp.Invoice, :generate_pdf, %{invoice_id: "123"})
{:ok, %AshTypst.Document{format: :pdf, data: pdf_binary}} = Ash.run_action(input)
```

## `typst` section options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `root` | `String.t \| {atom, String.t}` | `"priv/typst"` | Tuple form `{:my_app, "priv/typst"}` resolves via `Application.app_dir/2` at runtime — required for Mix releases. Plain relative strings only work when cwd is the project root (dev/test). |
| `font_paths` | list of same | `[]` | Same tuple recommendation. |
| `ignore_system_fonts` | boolean | `false` | |

## `template` entity

`template name do ... end` — one of:

- `source "path.typ"` — file path relative to `root`, read at render time
  (edits picked up without recompiling the resource)
- `markup ~TYPST"..."` — inline markup

Optional: `inputs %{"key" => "value"}` — static `sys.inputs` set for every
render using this template (string keys/values). Per-render dynamic values
should be action arguments instead (they reach the template as `args`).

## `render` entity

`render name do ... end` options:

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `template` | atom | required | Must reference a declared template (validated at compile time) |
| `format` | `:pdf \| :svg \| :html \| :bundle` | required | |
| `description` | string | | Action description |
| `page` | non_neg_integer | `0` | Page index for `:svg` |
| `pretty` | boolean | `false` | Human-readable HTML/SVG output (also within bundles) |
| `render_bleed` | boolean | `false` | Bleed margins for SVG (also within bundles) |
| `data_file` | string | `"data.typ"` | Virtual file path for injected data |
| `transaction?` | boolean | `false` | Wrap execution in a transaction |

Nested entities: `argument`, `read` (singleton), `pdf_options` (singleton),
`prepare`, `validate`.

### `argument name, type`

Standard Ash action arguments: `allow_nil?`, `default`, `constraints`,
`description`, `public?`, `sensitive?`. Note `sensitive?` redacts
logs/telemetry only — the value is still injected into `args` in the template.

### `read cardinality`

`:one` uses `Ash.read_one`, `:many` uses `Ash.read`. Options:

| Option | Notes |
| --- | --- |
| `filter` | Ash expression; `^arg(:name)` references action arguments |
| `load` | Relationships, calculations, aggregates to load |
| `select` | Attributes to select (`nil` = all). De-select what the template doesn't use — encoded payload is compile-time overhead |
| `sort` | Sort specification |
| `limit` | Max records (`:many` only) |
| `batch_size` | Streaming batch size, default 100 (`:many` only) |
| `not_found` | `:error` (default) or `nil` when `:one` finds no record |

### `pdf_options`

`pages` (1-indexed range string like `"1-3,5,7-9"`), `pdf_standards`
(`[:pdf_1_7 | :pdf_a_2b | :pdf_a_3b]`), `document_id`.

### `prepare` / `validate`

Standard Ash preparations and validations. Preparations declared here can
shape the read query; note preparation `on` defaults to `[:read]`.

## Runtime behavior

1. The action checks out a pooled context configured from the resource's
   `root`/`font_paths`/`ignore_system_fonts` (paths resolved via
   `AshTypst.PathResolver`).
2. Template markup is set (source files read fresh from disk each render).
3. Static template `inputs` are applied as `sys.inputs`.
4. Data is injected into the `data_file` virtual file:
   - no `read`: `#let args = (...)` only
   - `read :one`: `#let record = (...)` and `#let args = (...)`
   - `read :many`: `#let records = (...)` streamed in `batch_size` batches,
     then `args` appended
5. Reads run with `authorize?: true` and the calling actor/tenant.
6. Compile + export in the declared format. (`:bundle` skips the paged
   pre-compile; `export_bundle` compiles on its own.)
7. The context returns to the pool scrubbed (virtual files and inputs
   cleared).

Records are encoded with an **empty encoding context** — no timezone shifting.
`DateTime`s encode in UTC; for localized/timezone-formatted output, use
calculations (see `multi-language.md`).

## Result types

`AshTypst.Document` fields: `format`, `data`, `page_count`, `warnings`.
`data` is a PDF binary, SVG string, HTML string, or (for `:bundle`) a map of
relative path → binary. `AshTypst.Type.Document` is a custom Ash type for
storing/casting these structs.

Compile failures surface as an `AshTypst.Resource.Errors.CompileError` Ash
error built from the underlying diagnostics.

## Introspection

`AshTypst.Resource.Info`:

- `templates/1`, `template/2` (`{:ok, t} | :error`), `template!/2`
- `renders/1`
- `typst_root/1`, `typst_font_paths/1`, `typst_ignore_system_fonts/1`
  (generated option accessors returning `{:ok, value}`)
