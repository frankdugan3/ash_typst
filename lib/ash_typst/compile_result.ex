defmodule AshTypst.CompileResult do
  @moduledoc """
  The result of a successful `AshTypst.Context.compile/1`.

  ## Fields

    * `:page_count` — the number of pages in the compiled document
    * `:warnings` — a list of `AshTypst.Diagnostic` warnings emitted during
      compilation
  """
  defstruct page_count: 0, warnings: []
end
