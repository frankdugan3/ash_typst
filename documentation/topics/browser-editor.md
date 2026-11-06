# Browser editor

A Typst editor in the browser wants highlighting, syntax errors, completion,
hover, and go to definition while the person types. AshTypst ships the Typst
analysis for that as a WebAssembly module that runs in a Web Worker
(`AshTypst.Wasm`). It is the same Typst build as the NIF, so what the editor
says matches what the server renders.

The module only analyzes. It does not lay out or render, and it has no
font files (the server gives it the list of its fonts, `AshTypst.Wasm.fonts/1`).
Render the preview on the server with the NIF (for example
`AshTypst.Context.render_svg/2` on each change), and use the module for
everything that must answer at the speed of typing.

## The short version

1. `mix ash_typst.wasm.install` writes `worker.js`, `typst_wasm.js`, and
   `typst_wasm_bg.wasm` into `priv/static/ash_typst`.
2. Serve them as static files, gzip the `.wasm` (`phx.digest`), and give the
   page their digested URLs.
3. Start the worker with the URLs and `AshTypst.Wasm.identity/0`.
4. Send it the files of the document, and map its answers to your editor.

## Install

Each release has the module as a GitHub release asset, and the package has
its checksum. The module is the same on every platform. `mix
ash_typst.wasm.install` downloads it, verifies the checksum, and writes the
files, unless the directory already has the files of this version (as
`esbuild.install --if-missing`). After an upgrade of `ash_typst`, it
installs the new version. Run it in the setup and the deploy of your
assets:

```elixir
"assets.setup": ["ash_typst.wasm.install", "esbuild.install --if-missing"],
"assets.deploy": ["ash_typst.wasm.install", "esbuild default --minify", "phx.digest"]
```

Another directory:

```elixir
config :ash_typst, AshTypst.Wasm, out: "priv/static/vendor/ash_typst"
```

## Serve

In Phoenix, add the directory to the static paths, and `.wasm` to the files
that `phx.digest` compresses. The module is about 19 MB, and about 8 MB as
gzip:

```elixir
def static_paths, do: ~w(assets ash_typst fonts images favicon.ico robots.txt)
```

```elixir
config :phoenix, :gzippable_exts,
  ~w(.js .map .css .txt .text .html .json .svg .eot .ttf .wasm)
```

Give the page the URLs from `static_path`. In production they have the
digest of each file, so the browser keeps the files until a new release, and
the glue and the module of two releases never meet:

```elixir
assets = %{
  worker: static_path(socket, "/ash_typst/worker.js"),
  glue: static_path(socket, "/ash_typst/typst_wasm.js"),
  wasm: static_path(socket, "/ash_typst/typst_wasm_bg.wasm"),
  identity: AshTypst.Wasm.identity()
}
```

## The worker

```javascript
const worker = new Worker(assets.worker, { type: 'module' })
worker.postMessage({ id: 1, type: 'init', glue: assets.glue, wasm: assets.wasm, identity: assets.identity })
worker.postMessage({ id: 2, type: 'entry', path: 'main.typ' })
worker.postMessage({ id: 3, type: 'files', files: { 'main.typ': '= Hello\n#lorem(10)' } })
worker.postMessage({ id: 4, type: 'autocomplete', path: 'main.typ', cursor: 12, explicit: true })
worker.onmessage = ({ data }) => console.log(data) // {id, result} or {id, error}
```

| Request         | Arguments                                 | Result                                                    |
| --------------- | ----------------------------------------- | --------------------------------------------------------- |
| `init`          | `glue`, `wasm`, `identity`                | `{build}`                                                 |
| `entry`         | `path`                                    | `true`                                                    |
| `files`         | `files` (path to text), `removed` (paths) | `true`                                                    |
| `highlight`     | `path`                                    | `[from, to, class, ...]`                                  |
| `syntax_errors` | `path`                                    | `[{severity, message, from, to, hints}]`                  |
| `autocomplete`  | `path`, `cursor`, `explicit`              | `{from, items: [{label, apply, detail, kind}]}` or `null` |
| `tooltip`       | `path`, `cursor`                          | `{kind, text}` (`kind` is `text` or `code`) or `null`     |
| `definition`    | `path`, `cursor`                          | `{path, from, to}` or `null`                              |

Positions are UTF-16 offsets, as in JavaScript strings. `init` fails if the
module is not the build of the server (`identity`): run
`mix ash_typst.wasm.install` again after an upgrade.

The world is the one of the NIF: the entry file is the main file, the other
files are virtual files at their paths, and the library has the features of
the NIF. There are no fonts (font completions are empty) and no packages
(`@preview/...` imports do not resolve). Send data files (for example a
generated `data.typ`) as files, so that completion knows their fields.

## Editor adapters

The worker knows no editor. An adapter maps the requests to the editor:

| Request         | CodeMirror 6                          | Monaco                             |
| --------------- | ------------------------------------- | ---------------------------------- |
| `files`         | an update listener                    | `model.onDidChangeContent`         |
| `syntax_errors` | `setDiagnostics` (`@codemirror/lint`) | `monaco.editor.setModelMarkers`    |
| `highlight`     | mark decorations with the classes     | a `DocumentSemanticTokensProvider` |
| `autocomplete`  | a completion source                   | a `CompletionItemProvider`         |
| `tooltip`       | `hoverTooltip`                        | a `HoverProvider`                  |
| `definition`    | a key binding that opens the file     | a `DefinitionProvider`             |

The highlight classes are the CSS classes of Typst (`typ-key`,
`typ-heading`, ...). A completion `apply` can have snippet placeholders
(`${name}`): Monaco inserts them as a snippet, CodeMirror can remove them.
Monaco's `model.getPositionAt(offset)` converts an offset to a position.
