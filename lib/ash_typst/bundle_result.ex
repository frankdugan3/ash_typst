defmodule AshTypst.BundleResult do
  @moduledoc """
  Result of a successful `AshTypst.Context.export_bundle/2`.

  The `files` field is a map of relative path (no leading slash) to the rendered
  binary content, e.g. `%{"index.html" => "...", "logo.svg" => "..."}`. The
  `warnings` field is a list of `AshTypst.Diagnostic` warnings emitted during
  compilation.
  """
  defstruct files: %{}, warnings: []
end
