defmodule AshTypst.Sigil do
  @moduledoc ~S'''
  Provides the `~TYPST` sigil for Typst markup.

  The sigil returns the string as-is without interpolation or escaping.
  It clearly marks Typst source code for editor syntax highlighting, and
  checks the markup's syntax at compile time.

  ## Usage

      import AshTypst.Sigil

      ~TYPST"""
      = Hello World
      #import "data.typ": record
      *#record.name*
      """

  Since `~TYPST` is all uppercase, Elixir treats it as a raw sigil — `#`
  characters are passed through literally, which is exactly what Typst
  markup requires.

  ## Compile-time validation

  The markup is parsed (not evaluated) when the sigil is expanded. Syntax
  errors such as unclosed delimiters or malformed expressions fail
  compilation with an `AshTypst.Sigil.SyntaxError` pointing at the exact
  location inside the Elixir source file, and Typst syntax warnings are
  emitted as compiler warnings. Both surface inline in editors through the
  Elixir language servers.

  Because nothing is evaluated, imports, packages, `sys.inputs` and virtual
  files are not resolved: a template that imports `"data.typ"` validates even
  though that file only exists at render time. Errors that need evaluation
  (unknown variables, wrong argument types, missing files) are still reported
  when the template is compiled at runtime.

  Template files referenced by a resource's `source` option get the same
  check when the resource compiles (see `AshTypst.Resource`).
  '''

  alias AshTypst.SyntaxReport

  # Length of `~TYPST` plus a single-character opening delimiter.
  @inline_prefix byte_size("~TYPST") + 1

  @doc ~S'''
  Handles the `~TYPST` sigil for Typst markup.

  Returns the given string unchanged. Does not perform interpolation
  or escaping. Raises `AshTypst.Sigil.SyntaxError` at compile time when
  the markup is not valid Typst syntax.

  ## Examples

      iex> import AshTypst.Sigil
      iex> ~TYPST"= Hello"
      "= Hello"

      iex> import AshTypst.Sigil
      iex> ~TYPST"#let x = 1"
      "#let x = 1"

  '''
  defmacro sigil_TYPST({:<<>>, meta, [string]}, []) when is_binary(string) do
    validate!(string, meta, __CALLER__)
    string
  end

  @doc false
  def validate!(markup, meta, %Macro.Env{} = caller) do
    {errors, warnings} = SyntaxReport.diagnostics(markup)
    origin = origin(meta, caller)

    for warning <- warnings do
      {start, _} = SyntaxReport.locate(warning, markup, origin)
      IO.warn(SyntaxReport.format_message(warning), warn_location(caller.file, start))
    end

    case errors do
      [] ->
        :ok

      [first | _] ->
        {{line, column}, {end_line, end_column}} = SyntaxReport.locate(first, markup, origin)

        raise AshTypst.Sigil.SyntaxError,
          file: caller.file,
          line: line,
          column: column,
          end_line: column && end_line,
          end_column: column && end_column,
          description:
            Enum.map_join(errors, "\n\n", &SyntaxReport.format(&1, markup, origin, caller.file)),
          diagnostics: errors
    end
  end

  # Where the sigil's contents start in the Elixir file. Heredoc contents
  # begin on the line after the opening delimiter and have `indentation`
  # columns stripped from every line; inline contents start right after
  # `~TYPST` and its delimiter, on the same line, and any further lines of
  # an inline sigil start at column 1.
  defp origin(meta, caller) do
    line = Keyword.get(meta, :line, caller.line)

    case Keyword.fetch(meta, :indentation) do
      {:ok, indentation} ->
        %{line: line + 1, first_column: indentation + 1, column: indentation + 1}

      :error ->
        first_column = if column = meta[:column], do: column + @inline_prefix
        %{line: line, first_column: first_column, column: 1}
    end
  end

  defp warn_location(file, {line, nil}), do: [file: file, line: line]
  defp warn_location(file, {line, column}), do: [file: file, line: line, column: column]
end
