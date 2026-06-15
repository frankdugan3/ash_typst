defmodule AshTypst.Diagnostic do
  @moduledoc false
  defstruct [:severity, :message, :span, :trace, :hints]
end
