defmodule AshTypst.Document do
  @moduledoc """
  Wrapper struct for rendered Typst documents.

  This is the return type of all render actions declared via the `AshTypst.Resource`
  extension. The `format` field indicates which export was used and determines the
  shape of `data`:

    * `:pdf` — PDF binary
    * `:svg` — SVG string
    * `:html` — HTML string
    * `:bundle` — a map of relative path to rendered binary content
  """
  defstruct [:format, :data, :page_count, :warnings]
end
