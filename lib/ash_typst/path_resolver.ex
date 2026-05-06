defmodule AshTypst.PathResolver do
  @moduledoc """
  Resolves DSL path values to absolute filesystem paths at runtime.

  ## Why

  Mix releases relocate `priv/` files: in dev they live at
  `<project>/priv/...`; in a release at
  `<release>/lib/<app>-<version>/priv/...`. A literal relative string
  baked into a Spark DSL at compile time only works in dev.

  Mirroring the idiomatic `Plug.Static` pattern (`from: {:my_app, "priv/static"}`),
  AshTypst accepts either:

    * a `String.t()` — used verbatim (caller's responsibility to provide
      a path that resolves correctly in every environment), or
    * a `{atom(), String.t()}` tuple — resolved at runtime via
      `Application.app_dir/2`, which returns the correct absolute path
      in dev, test, and Mix releases.

  ## Examples

      iex> AshTypst.PathResolver.resolve("priv/typst")
      "priv/typst"

      iex> path = AshTypst.PathResolver.resolve({:ash_typst, "priv/typst"})
      iex> String.ends_with?(path, "ash_typst/priv/typst")
      true
  """

  @type path_spec :: String.t() | {atom(), String.t()}

  @doc """
  Returns an absolute (or as-given) path string.

    * String → returned as-is.
    * `{otp_app, sub_path}` → resolved via `Application.app_dir/2`.
  """
  @spec resolve(path_spec()) :: String.t()
  def resolve(path) when is_binary(path), do: path

  def resolve({otp_app, sub_path}) when is_atom(otp_app) and is_binary(sub_path) do
    Application.app_dir(otp_app, sub_path)
  end

  @doc """
  Resolves a list of `t:path_spec/0` values.
  """
  @spec resolve_all([path_spec()]) :: [String.t()]
  def resolve_all(paths) when is_list(paths), do: Enum.map(paths, &resolve/1)
end
