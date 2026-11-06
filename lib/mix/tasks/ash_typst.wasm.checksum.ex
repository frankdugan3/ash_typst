defmodule Mix.Tasks.AshTypst.Wasm.Checksum do
  @shortdoc "Writes the checksum of the released Typst editing module."
  @moduledoc """
  Downloads the archive of the Typst editing module of this version from the
  GitHub release and writes its checksum to `checksum-ash_typst_wasm.exs`.
  Run it before `mix hex.publish`, after the release workflow, as for the
  NIF checksums:

      mix rustler_precompiled.download AshTypst.NIF --all
      mix ash_typst.wasm.checksum

  `ASH_TYPST_WASM_BASE_URL` replaces the release URL.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    name = AshTypst.Wasm.archive_name()
    url = AshTypst.Wasm.base_url() <> "/" <> name

    case AshTypst.Wasm.fetch(url) do
      {:ok, body} ->
        checksum = AshTypst.Wasm.checksum(body)
        text = inspect(%{name => checksum}, pretty: true) <> "\n"
        File.write!(AshTypst.Wasm.checksum_file(), text)
        Mix.shell().info("#{name}: #{checksum}")

      {:error, message} ->
        Mix.raise(message)
    end
  end
end
