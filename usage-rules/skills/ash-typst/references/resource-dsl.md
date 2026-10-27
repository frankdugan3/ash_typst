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
| `encoding_context` | map | `%{}` | Context for `AshTypst.Code.encode/2`, used for `args` and the read results, e.g. `%{timezone: arg(:timezone)}`. Values accept `arg/1`, `actor/1`, `tenant/0`, `context/1`; entries resolving to `nil` are dropped |
| `transaction?` | boolean | `false` | Wrap execution in a transaction |
| `isolate?` | boolean | `false` | Compile and export in a throwaway OS process (`AshTypst.Isolated`); a streamed read runs from a task. Rejected with `transaction? true` and a streamed read |

Nested entities: `argument`, `read` (singleton), `pdf_options` (singleton),
`prepare`, `validate`.

### `argument name, type`

Standard Ash action arguments: `allow_nil?`, `default`, `constraints`,
`description`, `public?`, `sensitive?`. Note `sensitive?` redacts
logs/telemetry only — the value is still injected into `args` in the template.

### `read cardinality`

`:one` uses `Ash.read_one`, `:many` uses `Ash.stream!`. Options:

| Option | Notes |
| --- | --- |
| `action` | Read action to run; defaults to the primary read. Must exist and be a read (compile-time check) |
| `arguments` | Arguments for the read action, e.g. `%{location_id: arg(:location_id)}`. Keys must be arguments of the action (compile-time check). Templates supported |
| `filter` | Ash expression. Templates supported: `^arg(:name)`, `^actor(:field)`, `^tenant()`, `^context(:key)`, anywhere in the expression |
| `load` | Relationships, calculations, aggregates to load. Templates supported in calculation arguments: `load label: %{prefix: arg(:prefix)}` |
| `select` | Attributes to select (`nil` = all). De-select what the template doesn't use — encoded payload is compile-time overhead. No templates |
| `sort` | Sort specification. Templates supported in calculation arguments |
| `limit` | Max records (`:many` only). No templates |
| `batch_size` | Records fetched and encoded per batch, default 100 (`:many` only, not with `stream_with :none`). Capped at the action's `max_page_size` |
| `stream_with` | `:keyset \| :offset \| :none` (`:many` only). `:keyset`/`:offset` stream page by page with `Ash.stream!/2`; the action must support that pagination. `:none`: one unpaginated read, every record in memory; the action must not require pagination. **Required for `:many`** (no default), rejected on `:one`. All compile-time checked |
| `not_found` | `:one` only: `:error` (default) returns `Ash.Error.Query.NotFound`; `nil` renders with `record` set to `none` |

Templates outside `expr/1` are written without the pin: `arg(:name)`. An
`arg` naming an argument the render does not declare is a compile error, as
are `limit`/`batch_size`/`stream_with` on `:one`, `not_found nil` on
`:many`, and `batch_size` with `stream_with :none`.

A `nil` argument in a filter compares as `nil`: `location == ^arg(:location)`
matches no record when the argument is `nil`. Use `is_nil/1` or an `or` branch
if `nil` should mean "no filter".

#### Streaming and memory

`read :many` must set `stream_with`; there is no default, and a missing or
unsupported choice is a compile error that lists what the read action
supports.

- `stream_with :keyset` / `:offset`: streamed page by page. One page of
  `batch_size` records is fetched, encoded and appended to the data file
  before the next is fetched, so only one page is in memory at a time. The
  read action must support that pagination; the default `:read` action
  supports both. For a custom action:
  `pagination keyset?: true, required?: false`. Every matching record is
  returned (subject to `limit`) regardless of the action's
  `required?`/`default_limit`.
- `stream_with :none`: one unpaginated read (`page: false`), encoded in one
  go, all records in memory at once. Works on any action that does not set
  `required?: true`; `batch_size` and `preflight?` are rejected.
- Prefer `:keyset`: offset pages can shift if records are inserted or
  deleted during the render.
- Typst's own memory is the real cost: roughly 14× the data file to parse,
  7× for the evaluated records and ~100× for the laid-out pages, held in a
  memoization cache shared by the whole VM. After a streamed render
  (success, error or raise) the whole cache is evicted and trimmed back to
  the OS with `AshTypst.evict_cache/1`; the next render of any template
  starts cold. Fonts, template files and assets are kept. `stream_with
  :none`, `:one` and read-less renders keep the cache.
- Eviction lowers what stays resident, not the peak. If the peak may not
  fit, set `isolate? true` on the render: Typst runs in a peer OS process
  that exits afterwards, and the records stream from a task whose heap is
  freed when it exits. The read then runs outside the caller's process:
  `private? true` ETS tables appear empty and it can't join the render's
  transaction (`transaction? true` with a streamed read is a compile
  error).
- Ash appends a stable sort (primary key, or the action's `stable_sort`) to
  every page, so no unique `sort` is needed for correct paging.

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
   - `read :one`: `#let record = (...)` (`none` when nothing was found and
     `not_found nil`) and `#let args = (...)`
   - `read :many`: `#let records = (...)` streamed in `batch_size` batches,
     then `args` appended (with `stream_with :none`, encoded in one go)
5. Reads run as the caller: actor, tenant, tracer and `authorize?` are passed
   on (`authorize?` defaults to `true`; `Ash.run_action(input, authorize?:
   false)` also skips authorization of the read). The context of the render
   action input, including what its preparations set, is set on the read
   query.
6. Compile + export in the declared format. (`:bundle` skips the paged
   pre-compile; `export_bundle` compiles on its own.)
7. The context returns to the pool scrubbed (virtual files and inputs
   cleared).

Records and arguments are encoded with the render's `encoding_context`
(default: empty, so `DateTime`s encode in UTC). Set
`encoding_context %{timezone: arg(:timezone)}` to shift them; for
localized/formatted output, use calculations (see `multi-language.md`).

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
