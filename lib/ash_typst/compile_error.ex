defmodule AshTypst.CompileError do
  @moduledoc """
  Returned as `{:error, %AshTypst.CompileError{}}` when compilation or export
  fails.

  ## Fields

    * `:diagnostics` — a list of `AshTypst.Diagnostic` entries (the errors, and
      any related warnings) describing what went wrong
  """
  defstruct diagnostics: []
end
