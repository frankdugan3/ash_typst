defmodule Mix.Tasks.AshTypst.Wasm.Build do
  @shortdoc "Builds the Typst editing module (WASM) from source."
  @moduledoc """
  Builds the Typst editing module of the browser (`AshTypst.Wasm`) from the
  crate `typst_wasm` (`native/typst_nif/wasm`, in the Cargo workspace of the
  NIF), for the development of `ash_typst`. A host installs the released
  module (`mix ash_typst.wasm.install`).

      mix ash_typst.wasm.build
      mix ash_typst.wasm.build --release dist

  1. `cargo build -p typst_wasm --profile wasm --locked --target
     wasm32-unknown-unknown`
  2. `wasm-bindgen --target web`. Its version must be the version of the
     `wasm-bindgen` crate in `Cargo.lock` (wasm-bindgen refuses another).
  3. With `--release`: `wasm-opt -Oz` (binaryen), the release archive
     (`ash_typst_wasm-v<version>.tar.gz`) in the directory, and its
     checksum. The release workflow runs it.

  ## Options

  - `--out` - the directory of the files (no `--release`). Default:
    `AshTypst.Wasm.default_out/0`.
  - `--release` - the directory of the release archive.
  """

  use Mix.Task

  alias AshTypst.Wasm

  @target "wasm32-unknown-unknown"
  @profile "wasm"
  @switches [out: :string, release: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("loadconfig")

    case opts[:release] do
      nil ->
        out = opts[:out] || Wasm.default_out()
        build!(out, optimize: false)
        Wasm.stamp!(out)
        Mix.shell().info("Built the Typst editing module into #{out}.")

      dist ->
        files = Path.join(dist, "files")
        build!(files, optimize: true)

        archive = Path.join(dist, Wasm.archive_name())
        archive!(files, archive)
        Mix.shell().info("#{archive}: #{Wasm.checksum(File.read!(archive))}")
    end
  end

  defp build!(out, optimize: optimize?) do
    workspace = Wasm.workspace_dir()

    cmd!(
      "cargo",
      ["build", "-p", "typst_wasm", "--profile", @profile, "--locked", "--target", @target],
      cd: workspace
    )

    File.mkdir_p!(out)

    cmd!("wasm-bindgen", [
      "--target",
      "web",
      "--no-typescript",
      "--remove-name-section",
      "--remove-producers-section",
      "--out-dir",
      out,
      Path.join([workspace, "target", @target, @profile, "typst_wasm.wasm"])
    ])

    if optimize? do
      wasm = Path.join(out, "typst_wasm_bg.wasm")

      cmd!("wasm-opt", [
        "-Oz",
        "--enable-bulk-memory",
        "--enable-nontrapping-float-to-int",
        "--strip-debug",
        "--strip-producers",
        "-o",
        wasm,
        wasm
      ])
    end

    File.cp!(Path.join([workspace, "wasm", "js", "worker.js"]), Path.join(out, "worker.js"))
  end

  defp archive!(files, archive) do
    entries =
      for file <- Wasm.files() do
        {String.to_charlist(file), String.to_charlist(Path.join(files, file))}
      end

    File.mkdir_p!(Path.dirname(archive))
    :ok = :erl_tar.create(String.to_charlist(archive), entries, [:compressed])
  end

  defp cmd!(command, args, opts \\ []) do
    unless System.find_executable(command), do: Mix.raise("#{command} is not installed.")

    {_, status} =
      System.cmd(
        command,
        args,
        Keyword.merge([into: IO.stream(:stdio, :line), stderr_to_stdout: true], opts)
      )

    if status != 0, do: Mix.raise("#{command} failed with exit status #{status}.")
  end
end
