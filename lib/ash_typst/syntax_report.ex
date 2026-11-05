defmodule AshTypst.SyntaxReport do
  @moduledoc false
  # Shared compile-time reporting of Typst syntax diagnostics, used by the
  # `~TYPST` sigil and by the resource transformer that checks file templates.
  #
  # An `origin` describes where the markup's first character sits in the file
  # being reported against:
  #
  #   * `:line` — the line of the markup's first line
  #   * `:first_column` — the column of the markup's first line (`nil` when
  #     unknown, e.g. code quoted without column metadata)
  #   * `:column` — the column of every following line

  alias AshTypst.{Diagnostic, Span}

  @type origin :: %{line: pos_integer(), first_column: pos_integer() | nil, column: pos_integer()}

  @doc "The origin of markup that is the whole file, such as a `.typ` template."
  def file_origin, do: %{line: 1, first_column: 1, column: 1}

  @doc """
  Syntax diagnostics for `markup`, split into `{errors, warnings}`.

  Best effort: if the NIF is unavailable while compiling (for example a
  target without a precompiled build), returns no diagnostics rather than
  breaking compilation. Rendering reports the same problems at runtime.
  """
  def diagnostics(markup) do
    markup
    |> AshTypst.NIF.validate_syntax()
    |> Enum.split_with(&(&1.severity == :error))
  rescue
    UndefinedFunctionError ->
      {[], []}

    e in ErlangError ->
      if e.original == :not_loaded, do: {[], []}, else: reraise(e, __STACKTRACE__)
  end

  @doc """
  The `{line, column}` start and end of a diagnostic in the reported file.

  Empty ranges (e.g. "expected expression" at the end of input) are widened
  to one column so editors have something to underline.
  """
  def locate(%Diagnostic{span: nil}, _markup, origin) do
    {{origin.line, origin.first_column}, {origin.line, origin.first_column}}
  end

  def locate(%Diagnostic{span: %Span{start: from, end: to}}, markup, origin) do
    {line, column} = position(markup, from, origin)
    {end_line, end_column} = position(markup, to, origin)

    end_column =
      if {line, column} == {end_line, end_column} and column, do: column + 1, else: end_column

    {{line, column}, {end_line, end_column}}
  end

  @doc """
  Formats a diagnostic as `file:line:column: message`, followed by a snippet
  of the offending markup line with the range underlined, and any hints.
  """
  def format(%Diagnostic{} = diagnostic, markup, origin, file) do
    {{line, column}, _} = locate(diagnostic, markup, origin)

    location =
      file
      |> Path.relative_to_cwd()
      |> Exception.format_file_line_column(line, column)

    IO.iodata_to_binary([
      location,
      " ",
      diagnostic.message,
      snippet(diagnostic, markup, origin),
      format_hints(diagnostic.hints)
    ])
  end

  @doc "Formats a diagnostic's message and hints, without location or snippet."
  def format_message(%Diagnostic{message: message, hints: hints}) do
    IO.iodata_to_binary([message | format_hints(hints)])
  end

  defp format_hints(hints), do: Enum.map(hints, &"\n  hint: #{&1}")

  defp position(markup, offset, origin) do
    {line, column} = line_column(markup, offset)

    file_column =
      cond do
        line > 0 -> origin.column + column
        origin.first_column -> origin.first_column + column
        true -> nil
      end

    {origin.line + line, file_column}
  end

  # Zero-based line and codepoint column of a byte offset, matching how both
  # Typst and the Elixir compiler count columns.
  defp line_column(markup, offset) do
    lines = markup |> binary_part(0, offset) |> String.split("\n")
    {length(lines) - 1, lines |> List.last() |> String.to_charlist() |> length()}
  end

  # Renders the offending line of the markup, numbered by its line in the
  # reported file, with the range underlined (`^` for a point, `~` for a
  # range, which stops at the end of the line when it spans several lines).
  defp snippet(%Diagnostic{span: nil}, _markup, _origin), do: ""

  defp snippet(%Diagnostic{span: %Span{start: from, end: to}}, markup, origin) do
    {line, column} = line_column(markup, from)
    {end_line, end_column} = line_column(markup, to)
    text = markup |> String.split("\n") |> Enum.at(line)
    text_length = text |> String.to_charlist() |> length()

    width =
      cond do
        end_line > line -> max(text_length - column, 1)
        end_column > column -> end_column - column
        true -> 1
      end

    marker = if from == to, do: "^", else: String.duplicate("~", width)
    number = Integer.to_string(origin.line + line)
    gutter = String.duplicate(" ", byte_size(number) + 2)

    """

    #{gutter}│
     #{number} │ #{text}
    #{gutter}│ #{String.duplicate(" ", column)}#{marker}
    #{gutter}│\
    """
  end
end
