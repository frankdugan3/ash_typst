defmodule AshTypst.FontOptions do
  @moduledoc """
  Options for standalone font operations.
  """
  defstruct font_paths: [], ignore_system_fonts: false

  @type t :: %__MODULE__{
          font_paths: [String.t()],
          ignore_system_fonts: boolean()
        }
end
