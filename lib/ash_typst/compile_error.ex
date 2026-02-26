defmodule AshTypst.CompileError do
  @moduledoc "Error returned from a failed compilation."
  defstruct diagnostics: []

  @type t :: %__MODULE__{
          diagnostics: [AshTypst.Diagnostic.t()]
        }
end
