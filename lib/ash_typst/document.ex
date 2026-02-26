defmodule AshTypst.Document do
  @moduledoc """
  Wrapper struct for rendered Typst documents.

  This is the return type of all render actions declared via the `AshTypst.Resource`
  extension. The `data` field contains the raw binary output (PDF, SVG string, or
  HTML string) and `format` indicates which export was used.
  """
  defstruct [:format, :data, :page_count, :warnings]

  @type t :: %__MODULE__{
          format: :pdf | :svg | :html,
          data: binary(),
          page_count: non_neg_integer(),
          warnings: [AshTypst.Diagnostic.t()]
        }
end
