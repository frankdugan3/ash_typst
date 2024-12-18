defprotocol Typst.Code do
  @moduledoc """
  Encode Elixir data structures into Typst code syntax.
  """

  @doc """
  Convert Elixir data into Typst code.

  Context must be passed through. This allows for things like dates to be formatted according to a given timezone, etc.
  """
  def encode(value, context \\ [])
end

defimpl Typst.Code, for: Any do
  def encode(%{} = map, _context) when map_size(map) == 0, do: "(:)"

  def encode(map, context) do
    stripped = auto_strip(map)
    Typst.Code.encode(stripped, context)
  end

  case Code.ensure_compiled(Ash) do
    {:module, _} ->
      defp auto_strip(%{__struct__: module} = map) do
        if Ash.Resource.Info.resource?(module) do
          relationship_keys =
            module
            |> Ash.Resource.Info.public_relationships()
            |> Enum.map(& &1.name)

          selected_keys =
            module
            |> Ash.Resource.Info.public_attributes()
            |> Enum.reduce([], fn %{name: name}, acc ->
              if name in map.__metadata__.selected, do: [name | acc], else: acc
            end)

          Map.take(map, [:calculations, :aggregates] ++ relationship_keys ++ selected_keys)
        else
          Map.delete(map, :__struct__)
        end
      end

    _ ->
      defp auto_strip(%{__struct__: _} = map) do
        Map.delete(map, :__struct__)
      end
  end
end

defimpl Typst.Code, for: Map do
  @doc """
  An Elixir `Map` converts to a [Typst `dictionary`](https://typst.app/docs/reference/foundations/dictionary/).
  """

  def encode(%{} = map, _context) when map_size(map) == 0, do: "(:)"

  def encode(map, context) do
    fields =
      Enum.map_join(map, ", ", fn
        {key, value} -> "\"#{key}\": " <> Typst.Code.encode(value, context)
      end)

    "(#{fields})"
  end
end

defimpl Typst.Code, for: List do
  @doc """
  An Elixir `List` converts to a [Typst `array`](https://typst.app/docs/reference/foundations/array/).
  """
  def encode([], _context), do: "()"
  def encode([value], context), do: "(#{Typst.Code.encode(value, context)},)"

  def encode(list, context) do
    fields =
      Enum.map_join(list, ", ", fn value -> Typst.Code.encode(value, context) end)

    "(#{fields})"
  end
end

defimpl Typst.Code, for: DateTime do
  @doc """
  An Elixir `DateTime` converts to a [Typst `datetime`](https://typst.app/docs/reference/foundations/datetime/).

  If `timezone` is specified in the context, it will automatically be converted.

  Ensure you install and configure the timezone database in `config.exs`:

  ```elixir
  config :elixir, :time_zone_database, CustomTimeZoneDatabase
  ```
  """
  def encode(datetime, context) do
    timezone = context[:timezone] || "Etc/UTC"

    %{year: year, month: month, day: day, hour: hour, minute: minute, second: second} =
      DateTime.shift_zone!(datetime, timezone)

    "datetime(year: #{year}, month: #{month}, day: #{day}, hour: #{hour}, minute: #{minute}, second: #{second})"
  end
end

defimpl Typst.Code, for: NaiveDateTime do
  @doc """
  An Elixir `NaiveDateTime` converts to a [Typst `datetime`](https://typst.app/docs/reference/foundations/datetime/).
  """
  def encode(
        %{year: year, month: month, day: day, hour: hour, minute: minute, second: second},
        _context
      ) do
    "datetime(year: #{year}, month: #{month}, day: #{day}, hour: #{hour}, minute: #{minute}, second: #{second})"
  end
end

defimpl Typst.Code, for: Date do
  @doc """
  An Elixir `Date` converts to a [Typst `datetime`](https://typst.app/docs/reference/foundations/datetime/).
  """
  def encode(%{year: year, month: month, day: day}, _context) do
    "datetime(year: #{year}, month: #{month}, day: #{day})"
  end
end

defimpl Typst.Code, for: Time do
  @doc """
  An Elixir `Time` converts to a [Typst `datetime`](https://typst.app/docs/reference/foundations/datetime/).
  """
  def encode(
        %{hour: hour, minute: minute, second: second},
        _context
      ) do
    "datetime(hour: #{hour}, minute: #{minute}, second: #{second})"
  end
end

defimpl Typst.Code, for: Integer do
  @doc """
  An Elixir `Integer` converts to a [Typst `int`](https://typst.app/docs/reference/foundations/int/).
  """
  def encode(integer, _context), do: "int(#{integer})"
end

defimpl Typst.Code, for: Float do
  @doc """
  An Elixir `Float` converts to a [Typst `float`](https://typst.app/docs/reference/foundations/float/).
  """
  def encode(float, _context), do: "float(#{float})"
end

defimpl Typst.Code, for: BitString do
  @doc """
  An Elixir `BitString` converts to a [Typst `str`](https://typst.app/docs/reference/foundations/str/).
  """
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

defimpl Typst.Code, for: Atom do
  @doc """
  An Elixir `Atom` converts one of several Typst types:

  - `nil` -> [`none`](https://typst.app/docs/reference/foundations/none/)
  - `true`/`false` -> [`bool`](https://typst.app/docs/reference/foundations/bool/)
  - All others -> [`str`](https://typst.app/docs/reference/foundations/str/)
  """
  def encode(nil, _context), do: "none"
  def encode(true, _context), do: "true"
  def encode(false, _context), do: "false"
  def encode(atom, context), do: atom |> Atom.to_string() |> Typst.Code.encode(context)
end

case Code.ensure_compiled(Decimal) do
  {:module, _} ->
    defimpl Typst.Code, for: Decimal do
      @doc """
      An Elixir `Decimal` converts to a [Typst `decimal`](https://typst.app/docs/reference/foundations/decimal/).
      """
      def encode(decimal, _context), do: "decimal(#{decimal})"
    end

  _ ->
    :noop
end

case Code.ensure_compiled(Ash) do
  {:module, _} ->
    defimpl Typst.Code, for: Ash.NotLoaded do
      def encode(_, _context), do: "none"
    end

    defimpl Typst.Code, for: Ash.CiString do
      def encode(%{string: string}, context), do: Typst.Code.encode(string, context)
    end

  _ ->
    :noop
end
