defmodule AshTypst.CompileResult do
  @moduledoc "Result of a successful compilation."
  defstruct page_count: 0, warnings: []

  @type t :: %__MODULE__{
          page_count: non_neg_integer(),
          warnings: [AshTypst.Diagnostic.t()]
        }
end
