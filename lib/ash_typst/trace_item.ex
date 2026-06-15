defmodule AshTypst.TraceItem do
  @moduledoc """
  One entry in an `AshTypst.Diagnostic`'s call trace, identifying a step in the
  chain of function calls that led to the diagnostic.

  ## Fields

    * `:span` — an `AshTypst.Span` for this trace point, or `nil`
    * `:message` — a description of this step (e.g. the call site)
  """
  defstruct [:span, :message]
end
