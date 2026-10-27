defmodule AshTypst.Context.Options do
  @moduledoc """
  Configuration of a context.

  Accepted, as this struct or as a keyword list with the same keys, by
  `AshTypst.Context.new/1`, `AshTypst.ContextPool.with_context/2` and
  `AshTypst.Isolated.with_context/2`. The pool keeps a separate set of
  contexts for every distinct configuration.

    * `:root` — directory templates may read real files from (imports,
      images, data files). `nil` (the default) disables filesystem access
      entirely; see `AshTypst.Context.new/1`.
    * `:font_paths` — additional font directories to search (default `[]`)
    * `:ignore_system_fonts` — skip system fonts (default `false`)
  """
  defstruct root: nil, font_paths: [], ignore_system_fonts: false

  @type t :: %__MODULE__{
          root: String.t() | nil,
          font_paths: [String.t()],
          ignore_system_fonts: boolean()
        }
end
