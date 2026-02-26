defmodule AshTypst.Diagnostic do
  @moduledoc "A diagnostic message from the Typst compiler."
  defstruct [:severity, :message, :span, :trace, :hints]

  @type t :: %__MODULE__{
          severity: :error | :warning,
          message: String.t(),
          span: AshTypst.Span.t() | nil,
          trace: [AshTypst.TraceItem.t()],
          hints: [String.t()]
        }
end
