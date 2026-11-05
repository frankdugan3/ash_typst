defmodule AshTypst.Sigil.SyntaxError do
  @moduledoc """
  Raised at compile time when a `~TYPST` sigil contains invalid Typst syntax.

  The fields follow the conventions of Elixir's own compile errors, so the
  compiler reports the error with a precise source range and editors (via the
  Elixir LSPs) can underline it inline:

    * `:file`, `:line`, `:column` — the start of the first error in the
      Elixir source file
    * `:end_line`, `:end_column` — the end of that error's range
    * `:description` — the formatted report covering every syntax error found
    * `:diagnostics` — the raw `AshTypst.Diagnostic` entries, with spans
      relative to the sigil's contents
  """
  defexception [:file, :line, :column, :end_line, :end_column, :description, diagnostics: []]

  @impl true
  def message(%__MODULE__{description: description}), do: description
end
