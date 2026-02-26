defmodule AshTypst.Span do
  @moduledoc "Source location span with optional line/column."
  defstruct [:start, :end, :line, :column]

  @type t :: %__MODULE__{
          start: non_neg_integer(),
          end: non_neg_integer(),
          line: non_neg_integer() | nil,
          column: non_neg_integer() | nil
        }
end
