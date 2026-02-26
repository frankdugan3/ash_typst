defmodule AshTypst.Context.Options do
  @moduledoc "Options for creating a new context."
  defstruct root: ".", font_paths: [], ignore_system_fonts: false

  @type t :: %__MODULE__{
          root: String.t(),
          font_paths: [String.t()],
          ignore_system_fonts: boolean()
        }
end
