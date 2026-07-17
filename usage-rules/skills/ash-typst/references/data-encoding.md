# Data Encoding: the AshTypst.Code Protocol

`AshTypst.Code.encode(value, context)` converts Elixir values into Typst
*source code* — complete, well-formed Typst values that are safe anywhere an
expression is valid. This is why interpolation is never needed: encoded values
carry their own quoting/escaping.

## Type mapping

| Elixir | Typst |
| --- | --- |
| `Map` | dictionary `("key": value, ...)`; empty map → `(:)` |
| `List` | array `(a, b)`; empty → `()`; single → `(a,)` |
| `Integer` | `int(n)` |
| `Float` | `float(n)` |
| `Decimal` | `decimal("n")` |
| `String` (`BitString`) | `"escaped"` (escapes `\`, `"`, `\n`, `\r`, `\t`) |
| `DateTime` / `NaiveDateTime` / `Date` / `Time` | `datetime(...)` with the relevant components |
| `true` / `false` | `true` / `false` |
| `nil` | `none` |
| other atoms | `"string"` |
| `Ash.CiString` | `"string"` |
| `Ash.NotLoaded` | `none` (but see compaction — usually omitted first) |
| Ash resource (derived) | dictionary of public fields |

## Opting structs in

Structs (including Ash resources) are **not** encoded unless they opt in:

```elixir
@derive AshTypst.Code   # built-in implementation (public fields, see below)
# or full control:
defimpl AshTypst.Code, for: MyStruct do
  def encode(value, context), do: ...
end
```

Without opting in, encoding raises `Protocol.UndefinedError`. The
`AshTypst.Resource` extension validates the derive at compile time for
resources whose render actions declare a `read`.

## Query-level compaction (built-in Ash resource implementation)

The emitted dictionary carries only what the query actually produced:

- **Private fields are excluded entirely** — only `public?: true` fields.
- **Not produced = omitted.** Attributes excluded via `select` and
  relationships/calculations/aggregates not loaded do not appear at all — not
  even as `none`.
- **Loaded-but-empty = `none`.** A `belongs_to` that resolved to `nil` or a
  nullable attribute the query did select encodes as `none`, keeping "no
  value" distinct from "not queried".
- **Forbidden fields are omitted silently** (`Ash.ForbiddenField` from field
  policies) — authorization-filtered reads render without leaking or erroring.
- **Ad hoc calculations/aggregates** (loaded on the query rather than declared
  on the resource) appear as dictionaries under `calculations` / `aggregates`
  keys; the keys are dropped when empty.

Template idiom for fields that may or may not have been queried:

```typ
#let notes = record.at("notes", default: none)
#if notes != none [ == Notes \ #notes ]
```

Performance: encoded output is Typst source parsed and evaluated on **every
compile** — payload size is compile time. De-select unused attributes,
especially for large `:many` renders.

## Encoding context

The second argument is a map threaded through the whole encode:

- `timezone: "America/New_York"` — `DateTime`s are shifted to that zone before
  encoding. Requires a configured time-zone database, e.g.
  `config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase`. Without it,
  `DateTime`s encode in `Etc/UTC`.
- `struct_keys: %{MyApp.Invoice => [:id, :total]}` — take exactly those keys
  for that struct instead of the automatic public-field stripping. Useful as
  an explicit, greppable per-render field selection.

Render actions encode with an empty context (`%{}`) — no timezone shifting;
use calculations for localized/zone-formatted values (see
`multi-language.md`). Direct `stream_virtual_file/4` accepts `context:` to
pass one.

## Key order

Dictionary keys are emitted in Erlang's native map iteration order —
deliberately unsorted for speed. That order is not defined across VM runs:
templates must access fields by name (or sort explicitly when iterating), and
byte-identical output across runs is not guaranteed.

## Examples

```elixir
AshTypst.Code.encode(~U[2015-01-13 13:00:07Z], %{timezone: "America/New_York"})
#=> "datetime(year: 2015, month: 1, day: 13, hour: 8, minute: 0, second: 7)"

AshTypst.Code.encode(["one", 2, 3.0], %{})
#=> "(\"one\", int(2), float(3.0))"

AshTypst.Code.encode(%{name: "Acme", active: true, note: nil}, %{})
#=> "(\"name\": \"Acme\", \"active\": true, \"note\": none)"
```

Building a data virtual file by hand:

```elixir
data = "#let record = #{AshTypst.Code.encode(record, %{})}\n"
:ok = AshTypst.Context.set_virtual_file(ctx, "data.typ", data)
```
