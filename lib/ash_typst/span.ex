defmodule AshTypst.Span do
  @moduledoc """
  A source location range within a Typst file, attached to an
  `AshTypst.Diagnostic` or `AshTypst.TraceItem`.

  ## Fields

    * `:start` — zero-based byte offset of the start of the range
    * `:end` — zero-based byte offset of the end of the range
    * `:line` — one-based line number of the start, or `nil` when it could not
      be resolved
    * `:column` — one-based column number of the start, or `nil` when it could
      not be resolved
  """
  defstruct [:start, :end, :line, :column]
end
