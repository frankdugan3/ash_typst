defprotocol AshTypst.Code do
  @moduledoc """
  Protocol to support Typst code syntax.
  """

  @doc """
  Encode Elixir data structures into Typst code syntax.

  ## Examples

      iex> AshTypst.Code.encode(~U[2015-01-13 13:00:07Z], %{timezone: "America/New_York"})
      "datetime(year: 2015, month: 1, day: 13, hour: 8, minute: 0, second: 7)"

      iex> AshTypst.Code.encode(nil)
      "none"

      iex> AshTypst.Code.encode(%{true: true, false: false, other: :other})
      "(\\"false\\": false, \\"true\\": true, \\"other\\": \\"other\\")"

      iex> AshTypst.Code.encode(["one", 2, 3.0])
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

  Context must be passed through. This allows for things like dates to be formatted according to a given timezone, etc.

  If `timezone` is specified in the context, supported types will be automatically shifted to that zone. Ensure you install and configure your choice of timezone database in `config.exs`:

  ```elixir
  config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
  config :elixir, :time_zone_database, TimeZoneInfo.TimeZoneDatabase
  config :elixir, :time_zone_database, Zoneinfo.TimeZoneDatabase
  config :elixir, :time_zone_database, Tz.TimeZoneDatabase
  ```

  """
  @spec encode(any(), map()) :: String.t()
  def encode(value, context \\ %{})
end

defimpl AshTypst.Code, for: Any do
  @spec encode(any(), map()) :: String.t()
  def encode(%{} = map, _context) when map_size(map) == 0, do: "(:)"

  @spec encode(struct(), map()) :: String.t()
  def encode(%{__struct__: module} = map, %{struct_keys: struct_keys} = context) do
    stripped =
      case struct_keys do
        %{^module => keys} -> Map.take(map, keys)
        _ -> auto_strip(map)
      end

    AshTypst.Code.encode(stripped, context)
  end

  @spec encode(map(), map()) :: String.t()
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
    loadable_keys =
      map.__struct__
      |> Ash.Resource.Info.public_fields()
      |> Enum.reduce([], fn
        %{name: name, type: :attribute}, acc ->
          if name in map.__metadata__.selected, do: [name | acc], else: acc

        %{name: name}, acc ->
          [name | acc]
      end)

    Map.take(map, [:calculations, :aggregates] ++ loadable_keys)
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
    timezone = context.timezone || "Etc/UTC"

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
  def encode(decimal, _context), do: "decimal(#{decimal})"
end

defimpl AshTypst.Code, for: Ash.NotLoaded do
  def encode(_, _context), do: "none"
end

defimpl AshTypst.Code, for: Ash.CiString do
  def encode(%{string: string}, context), do: AshTypst.Code.encode(string, context)
end
