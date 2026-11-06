defmodule AshTypst.Wasm do
  @moduledoc """
  The Typst editing module for a browser editor: highlighting, syntax
  errors, completion, hover, and go to definition, in a Web Worker. The
  server renders (the NIF). The browser only analyzes, thus it needs no
  font files (only the list of the fonts, refer to "Fonts").

  The module is the WASM build of the crate `typst_wasm`
  (`native/typst_nif/wasm`). It is in the Cargo workspace of the NIF, with
  one lock, thus the parser and the analysis in the browser are the ones of
  the server. It knows no editor: the input is files (path and text), and
  the output is plain data with UTF-16 offsets. An editor adapter
  (CodeMirror, Monaco, ...) maps it.

  ## Install

  Each release of `ash_typst` has the module as a GitHub release asset. The
  package has its checksum. The module is the same on each platform.
  `mix ash_typst.wasm.install` copies it into the static files of the host
  if they do not have the files of this version (as `esbuild.install
  --if-missing`), thus add it to the asset aliases:

      "assets.setup": ["ash_typst.wasm.install", ...],
      "assets.deploy": ["ash_typst.wasm.install", ..., "phx.digest"]

  The files go to `priv/static/ash_typst`:

  | File | Function |
  | --- | --- |
  | `worker.js` | The Web Worker (ES module). |
  | `typst_wasm.js` | The wasm-bindgen glue, which the worker loads. |
  | `typst_wasm_bg.wasm` | The module. |

  Another directory:

      config :ash_typst, AshTypst.Wasm, out: "priv/static/vendor/ash_typst"

  In a Phoenix host, add `ash_typst` to the static paths, and `.wasm` to the
  files that `phx.digest` compresses (the module is about 4 times smaller
  as gzip):

      config :phoenix, :gzippable_exts,
        ~w(.js .map .css .txt .text .html .json .svg .eot .ttf .wasm)

  Give the browser the digested URLs (`Phoenix.VerifiedRoutes.static_path/2`)
  of the three files, so that it keeps them until a new release.

  ## The worker

      const worker = new Worker(workerUrl, { type: "module" })
      worker.postMessage({ id: 1, type: "init", glue: glueUrl, wasm: wasmUrl, identity })
      worker.postMessage({ id: 2, type: "files", files: { "main.typ": "= Hello" } })
      worker.postMessage({ id: 3, type: "autocomplete", path: "main.typ", cursor: 7, explicit: true })

  Each request is `{id, type, ...}`, and each answer is `{id, result}` or
  `{id, error}`. `identity` is `identity/0` of the server: the worker does
  not start if the module is of another build. The requests and their
  results are in the head of `worker.js`.

  The world is the one of the NIF: the entry file is the main file (`entry`
  sets it, the default is `main.typ`), the other files are virtual files at
  their paths, and the library has the features of the NIF. There are no
  packages.

  ## Fonts

  The module has no font files: it only needs the list of the fonts, for
  the completion and the hover of `text(font: "...")`, and for the warning
  `unknown font family` on a literal family name of `text` (a call or a set
  rule). `fonts/1` gives the list of a context, thus the editor knows the
  fonts that the server renders with. Give it to the worker in `init`
  (`fonts`), or in a `fonts` request:

      worker.postMessage({ id: 4, type: "fonts", fonts })

  A `fonts` request replaces the list. Send it again when the editor
  changes to a context with other fonts. Without a list, there are no font
  completions and no font warnings.

  Each entry is a map (`t:AshTypst.Context.font_face/0`), as JSON. Only
  `family` is necessary, and a plain string is a family too:

      [{"family": "Inter", "style": "normal", "weight": 400}, "Fira Math"]
  """

  @version Mix.Project.config()[:version]
  @package_dir Path.expand("../..", __DIR__)

  @default_base_url "https://github.com/frankdugan3/ash_typst/releases/download/v#{@version}"

  @doc """
  The directory of the module files: `:out` of `config :ash_typst,
  AshTypst.Wasm`, or `priv/static/ash_typst`.
  """
  @spec default_out() :: String.t()
  def default_out do
    :ash_typst
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:out, "priv/static/ash_typst")
  end

  @doc """
  The identity of the server build: the `ash_typst` version and the version
  of the Typst crates of the NIF. The worker compares it with the build of
  the module (`init`).
  """
  @spec identity() :: %{version: String.t(), typst: String.t()}
  def identity, do: %{version: @version, typst: AshTypst.NIF.typst_version()}

  @doc """
  The fonts of a context, for the worker (`init` or a `fonts` request).
  Encode the list as JSON. Refer to "Fonts" in the module documentation.
  """
  @spec fonts(term()) :: [AshTypst.Context.font_face()]
  defdelegate fonts(ctx), to: AshTypst.Context, as: :font_faces

  @doc "The files of the module. Refer to the module documentation."
  @spec files() :: [String.t()]
  def files, do: ["typst_wasm.js", "typst_wasm_bg.wasm", "worker.js"]

  @doc false
  # The Cargo workspace of the NIF and the module.
  @spec workspace_dir() :: String.t()
  def workspace_dir, do: Path.join(@package_dir, "native/typst_nif")

  @doc false
  @spec checksum_file() :: String.t()
  def checksum_file, do: Path.join(@package_dir, "checksum-ash_typst_wasm.exs")

  @doc false
  # The release archive of this version.
  @spec archive_name() :: String.t()
  def archive_name, do: "ash_typst_wasm-v#{@version}.tar.gz"

  @doc false
  # The release URL, or `ASH_TYPST_WASM_BASE_URL` (a mirror). A `file://`
  # URL reads a local directory.
  @spec base_url() :: String.t()
  def base_url, do: System.get_env("ASH_TYPST_WASM_BASE_URL") || @default_base_url

  @doc false
  @spec checksums() :: %{String.t() => String.t()}
  def checksums do
    case File.read(checksum_file()) do
      {:ok, text} ->
        {map, _binding} = Code.eval_string(text)
        map

      {:error, _reason} ->
        %{}
    end
  end

  @doc """
  Downloads the release archive of the module, verifies its checksum, and
  writes its files into `out_dir`. Does nothing if `out_dir` has the files of
  this version, unless `force: true`.

  Options: `:base_url` (`base_url/0`), `:checksums` (the checksum file of the
  package), `:force`.
  """
  @spec install(Path.t(), keyword()) :: :ok | :noop | {:error, String.t()}
  def install(out_dir, opts \\ []) do
    if installed?(out_dir) and not Keyword.get(opts, :force, false) do
      :noop
    else
      name = archive_name()
      checksums = Keyword.get_lazy(opts, :checksums, &checksums/0)
      url = Keyword.get_lazy(opts, :base_url, &base_url/0) <> "/" <> name

      with {:ok, expected} <- expected_checksum(checksums, name),
           {:ok, body} <- fetch(url),
           :ok <- verify(body, expected, url) do
        extract!(body, out_dir)
      end
    end
  end

  @doc "Returns `true` if `out_dir` has the files of this version."
  @spec installed?(Path.t()) :: boolean()
  def installed?(out_dir) do
    File.read(Path.join(out_dir, ".version")) == {:ok, @version} and
      Enum.all?(files(), &File.exists?(Path.join(out_dir, &1)))
  end

  @doc false
  # Marks `out_dir` as the files of this version (after an install or a build).
  @spec stamp!(Path.t()) :: :ok
  def stamp!(out_dir), do: File.write!(Path.join(out_dir, ".version"), @version)

  defp expected_checksum(checksums, name) do
    case Map.fetch(checksums, name) do
      {:ok, checksum} ->
        {:ok, checksum}

      :error ->
        {:error,
         "The package has no checksum of #{name} (not a Hex release?). Build the module from source: mix ash_typst.wasm.build"}
    end
  end

  @doc false
  # The checksum of an archive, as in the checksum file.
  @spec checksum(binary()) :: String.t()
  def checksum(body), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)

  defp verify(body, expected, url) do
    actual = checksum(body)

    if actual == expected,
      do: :ok,
      else: {:error, "The checksum of #{url} is #{actual}, but the package expects #{expected}."}
  end

  # Only the files of the module are extracted, thus an archive cannot write
  # other paths.
  defp extract!(body, out_dir) do
    File.mkdir_p!(out_dir)

    :ok =
      :erl_tar.extract(
        {:binary, body},
        [
          :compressed,
          cwd: String.to_charlist(out_dir),
          files: Enum.map(files(), &String.to_charlist/1)
        ]
      )

    stamp!(out_dir)
  end

  @doc false
  # Reads an `http(s)://` or a `file://` URL.
  @spec fetch(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def fetch("file://" <> path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, "Cannot read #{path}: #{:file.format_error(reason)}"}
    end
  end

  def fetch(url) do
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, "#{url} answered #{status}."}
      {:error, reason} -> {:error, "Cannot download #{url}: #{inspect(reason)}"}
    end
  end
end
