defmodule AshTypst.TraceItem do
  @moduledoc "A trace item in a diagnostic."
  defstruct [:span, :message]

  @type t :: %__MODULE__{
          span: AshTypst.Span.t() | nil,
          message: String.t()
        }
end
