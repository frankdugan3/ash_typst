defmodule Mix.Tasks.AshTypst.Wasm.Install do
  @shortdoc "Installs the Typst editing module (WASM) into the static files, if missing."
  @moduledoc """
  Installs the Typst editing module of the browser (`AshTypst.Wasm`) if the
  directory does not have the files of this `ash_typst` version: downloads
  the archive of this version from the GitHub release, verifies its
  checksum (in the package), and writes its files. Thus it is safe in the
  asset aliases, as `esbuild.install --if-missing`:

      "assets.setup": ["ash_typst.wasm.install", ...]

  The directory is `:out` of `config :ash_typst, AshTypst.Wasm`, or
  `priv/static/ash_typst`.

  ## Options

  - `--out` - another directory.
  - `--force` - installs again.

  `ASH_TYPST_WASM_BASE_URL` replaces the release URL (a mirror, or a
  `file://` directory).
  """

  use Mix.Task

  @switches [out: :string, force: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("loadconfig")
    out = opts[:out] || AshTypst.Wasm.default_out()

    case AshTypst.Wasm.install(out, force: opts[:force] || false) do
      :ok -> Mix.shell().info("Installed the Typst editing module into #{out}.")
      :noop -> :ok
      {:error, message} -> Mix.raise(message)
    end
  end
end
