defprotocol AshTypst.Code do
  @moduledoc """
  Protocol to support Typst code syntax.
  """

  @doc """
  Encode Elixir data structures into Typst code syntax.

  ## Examples

      iex> AshTypst.Code.encode(~U[2015-01-13 13:00:07Z], %{timezone: "America/New_York"})
      "datetime(year: 2015, month: 1, day: 13, hour: 8, minute: 0, second: 7)"

      iex> AshTypst.Code.encode(nil, %{})
      "none"

      iex> AshTypst.Code.encode(%{true: true, false: false, other: :other}, %{})
      "(\\"false\\": false, \\"true\\": true, \\"other\\": \\"other\\")"

      iex> AshTypst.Code.encode(["one", 2, 3.0], %{})
      "(\\"one\\", int(2), float(3.0))"

  The following types are supported by default:

  - `Map` -> [`dictionary`](https://typst.app/docs/reference/foundations/dictionary/)
  - `List` -> [`array`](https://typst.app/docs/reference/foundations/array/)
  - `Decimal` -> [`decimal`](https://typst.app/docs/reference/foundations/decimal/)
  - `DateTime` -> [`datetime`](https://typst.app/docs/reference/foundations/datetime/)
  - `NaiveDateTime` -> [`datetime`](https://typst.app/docs/reference/foundations/datetime/)
  - `Date` -> [`datetime`](https://typst.app/docs/reference/foundations/datetime/)
  - `Time` -> [`datetime`](https://typst.app/docs/reference/foundations/datetime/)
  - `Integer` -> [`int`](https://typst.app/docs/reference/foundations/int/)
  - `Float` -> [`float`](https://typst.app/docs/reference/foundations/float/)
  - `String` -> [`str`](https://typst.app/docs/reference/foundations/str/)
  - `Atom` converts one of several Typst types:
    - `nil` -> [`none`](https://typst.app/docs/reference/foundations/none/)
    - `true`/`false` -> [`bool`](https://typst.app/docs/reference/foundations/bool/)
    - All others -> [`str`](https://typst.app/docs/reference/foundations/str/)
  - `Ash.Resource` (public fields) -> [`dictionary`](https://typst.app/docs/reference/foundations/dictionary/)
  - `Ash.NotLoaded` -> [`none`](https://typst.app/docs/reference/foundations/none/)
  - `Ash.CiString` -> [`str`](https://typst.app/docs/reference/foundations/str/)

  Structs (including Ash resources) are not encoded unless they opt in. Add
  `@derive AshTypst.Code` to the module to use the built-in implementation
  (which serializes an Ash resource's public fields), or implement the protocol
  directly with `defimpl AshTypst.Code, for: MyStruct` for full control:

  ```elixir
  defmodule MyApp.Invoice do
    use Ash.Resource, domain: MyApp.Domain

    @derive AshTypst.Code

    # ...
  end
  ```

  ## Query-level compaction

  The built-in Ash resource implementation carries only the data your query
  actually produced. Every public field appears as a key in the emitted
  dictionary, but the *values* follow the query:

  - **Private fields are excluded entirely** — only `public?: true` fields
    are considered.
  - **Anything the query did not produce is omitted.** Attributes excluded
    via `Ash.Query.select/2` (or the `select` option of a render action's
    `read` block) and relationships, calculations, or aggregates that were
    not loaded do not appear in the dictionary at all — not even as `none`.
  - **Loaded-but-empty is preserved.** A field the query *did* produce with
    an empty result (e.g. a `belongs_to` that resolved to `nil`) encodes as
    `none`, keeping "no value" distinct from "not queried".
  - **Forbidden fields are omitted silently.** A field redacted by a field
    policy (`Ash.ForbiddenField`) is dropped, the same as not-loaded.
  - **Anonymous calculations and aggregates live under `calculations` /
    `aggregates`.** Calculations and aggregates loaded ad hoc on the query
    (rather than declared on the resource) are encoded as dictionaries under
    those two keys; when empty, the keys are dropped.

  The encoded output is Typst *source code* that the compiler must parse and
  evaluate on every compile, so payload size translates directly into
  compilation time. Because the payload follows the query, it is ideal to
  de-select attributes your template does not use — especially for large
  documents rendering thousands of records, where a few unused text columns
  can multiply the data the Typst compiler has to chew through:

  ```elixir
  read :many do
    select [:name, :amount, :inserted_at]
    load [:line_items]
  end
  ```

  Ideally a template references only fields its query provides, so absent
  keys are never an issue. If a single template is shared by actions with
  *different* query loads, read the varying fields with a default:
  `record.at("field", default: none)`.

  ## Key order

  Dictionary keys are emitted in Erlang's native map iteration order — they
  are deliberately *not* sorted, to keep encoding fast for large datasets.
  That order is not defined across VM runs, so templates should access fields
  by name (or sort explicitly when iterating) rather than rely on key order,
  and byte-identical output across runs is not guaranteed.

  To override which keys are encoded for a given struct, pass `struct_keys`
  in the context — a map of struct module to the exact keys to take:

      AshTypst.Code.encode(record, %{struct_keys: %{MyApp.Invoice => [:id, :total]}})

  Context must be passed through. This allows for things like dates to be formatted according to a given timezone, etc.

  If `timezone` is specified in the context, supported types will be automatically shifted to that zone. Ensure you install and configure your choice of timezone database in `config.exs`:

  ```elixir
  config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
  config :elixir, :time_zone_database, TimeZoneInfo.TimeZoneDatabase
  config :elixir, :time_zone_database, Zoneinfo.TimeZoneDatabase
  config :elixir, :time_zone_database, Tz.TimeZoneDatabase
  ```

  """
  def encode(value, context)
end

defimpl AshTypst.Code, for: Any do
  def encode(%{} = map, _context) when map_size(map) == 0, do: "(:)"

  def encode(%{__struct__: module} = map, %{struct_keys: struct_keys} = context) do
    stripped =
      case struct_keys do
        %{^module => keys} -> Map.take(map, keys)
        _ -> auto_strip(map)
      end

    AshTypst.Code.encode(stripped, context)
  end

  def encode(map, context) do
    stripped = auto_strip(map)
    AshTypst.Code.encode(stripped, context)
  end

  @struct_drop_keys [:__struct__]

  defp auto_strip(%{__struct__: module} = map) do
    if Ash.Resource.Info.resource?(module) do
      strip_ash_resource(map)
    else
      Map.drop(map, @struct_drop_keys)
    end
  end

  defp strip_ash_resource(map) do
    public_keys = Enum.map(Ash.Resource.Info.public_fields(map.__struct__), & &1.name)

    map
    |> Map.take([:calculations, :aggregates] ++ public_keys)
    |> Map.reject(fn
      {_key, %Ash.NotLoaded{}} -> true
      {_key, %Ash.ForbiddenField{}} -> true
      {key, value} when key in [:calculations, :aggregates] -> value == %{}
      {_key, _value} -> false
    end)
  end
end

defimpl AshTypst.Code, for: Map do
  def encode(%{} = map, _context) when map_size(map) == 0, do: "(:)"

  def encode(map, context) do
    fields =
      Enum.map_join(map, ", ", fn
        {key, value} -> "\"#{key}\": " <> AshTypst.Code.encode(value, context)
      end)

    "(#{fields})"
  end
end

defimpl AshTypst.Code, for: List do
  def encode([], _context), do: "()"
  def encode([value], context), do: "(#{AshTypst.Code.encode(value, context)},)"

  def encode(list, context) do
    fields =
      Enum.map_join(list, ", ", fn value -> AshTypst.Code.encode(value, context) end)

    "(#{fields})"
  end
end

defimpl AshTypst.Code, for: DateTime do
  def encode(datetime, context) do
    timezone = Map.get(context, :timezone, "Etc/UTC")

    %{year: year, month: month, day: day, hour: hour, minute: minute, second: second} =
      DateTime.shift_zone!(datetime, timezone)

    "datetime(year: #{year}, month: #{month}, day: #{day}, hour: #{hour}, minute: #{minute}, second: #{second})"
  end
end

defimpl AshTypst.Code, for: NaiveDateTime do
  def encode(
        %{year: year, month: month, day: day, hour: hour, minute: minute, second: second},
        _context
      ) do
    "datetime(year: #{year}, month: #{month}, day: #{day}, hour: #{hour}, minute: #{minute}, second: #{second})"
  end
end

defimpl AshTypst.Code, for: Date do
  def encode(%{year: year, month: month, day: day}, _context) do
    "datetime(year: #{year}, month: #{month}, day: #{day})"
  end
end

defimpl AshTypst.Code, for: Time do
  def encode(
        %{hour: hour, minute: minute, second: second},
        _context
      ) do
    "datetime(hour: #{hour}, minute: #{minute}, second: #{second})"
  end
end

defimpl AshTypst.Code, for: Integer do
  def encode(integer, _context), do: "int(#{integer})"
end

defimpl AshTypst.Code, for: Float do
  def encode(float, _context), do: "float(#{float})"
end

defimpl AshTypst.Code, for: BitString do
  def encode(string, _context) do
    escaped =
      string
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"#{escaped}\""
  end
end

defimpl AshTypst.Code, for: Atom do
  def encode(nil, _context), do: "none"
  def encode(true, _context), do: "true"
  def encode(false, _context), do: "false"
  def encode(atom, context), do: atom |> Atom.to_string() |> AshTypst.Code.encode(context)
end

defimpl AshTypst.Code, for: Decimal do
  def encode(decimal, _context), do: "decimal(\"#{decimal}\")"
end

defimpl AshTypst.Code, for: Ash.NotLoaded do
  def encode(_, _context), do: "none"
end

defimpl AshTypst.Code, for: Ash.CiString do
  def encode(%{string: string}, context), do: AshTypst.Code.encode(string, context)
end
