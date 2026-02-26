defmodule AshTypst.Sigil do
  @moduledoc ~S'''
  Provides the `~TYPST` sigil for Typst markup.

  The sigil returns the string as-is without interpolation or escaping.
  Its purpose is to clearly mark Typst source code for editor syntax
  highlighting and potential future formatting.

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
  '''

  @doc ~S'''
  Handles the `~TYPST` sigil for Typst markup.

  Returns the given string unchanged. Does not perform interpolation
  or escaping.

  ## Examples

      iex> import AshTypst.Sigil
      iex> ~TYPST"= Hello"
      "= Hello"

      iex> import AshTypst.Sigil
      iex> ~TYPST"#let x = 1"
      "#let x = 1"

  '''
  defmacro sigil_TYPST({:<<>>, _meta, [string]}, []) when is_binary(string) do
    string
  end
end
