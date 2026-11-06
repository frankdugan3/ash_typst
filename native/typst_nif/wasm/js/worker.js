// The Web Worker of the Typst editing module (`typst_wasm`): highlighting,
// syntax errors, completion, hover, and go to definition. It knows no
// editor. An editor (CodeMirror, Monaco, ...) sends requests and maps the
// answers. Refer to `AshTypst.Wasm`.
//
//   const worker = new Worker(workerUrl, { type: "module" })
//   worker.postMessage({ id: 1, type: "init", glue, wasm, identity })
//
// Each request is `{id, type, ...arguments}`. Each answer is `{id, result}`
// or `{id, error}` (a message). Positions are UTF-16 offsets.
//
// | type            | arguments                  | result                                   |
// | --------------- | -------------------------- | ---------------------------------------- |
// | `init`          | `glue`, `wasm`, `identity`, `fonts` | `{build}`                       |
// | `entry`         | `path`                     | `true`                                   |
// | `files`         | `files`, `removed`         | `true`                                   |
// | `fonts`         | `fonts`                    | `true`                                   |
// | `highlight`     | `path`                     | `[from, to, class, ...]`                 |
// | `syntax_errors` | `path`                     | `[{severity, message, from, to, hints}]` |
// | `autocomplete`  | `path`, `cursor`, `explicit` | `{from, items: [{label, apply, detail, kind}]}` or `null` |
// | `tooltip`       | `path`, `cursor`           | `{kind: "text" or "code", text}` or `null` |
// | `definition`    | `path`, `cursor`           | `{path, from, to}` or `null`             |
//
// `init` loads the wasm-bindgen glue (`glue`, the URL of `typst_wasm.js`)
// and the module (`wasm`, the URL of `typst_wasm_bg.wasm`). The URLs come
// from the page, thus a digested URL keeps the glue and the module of one
// build together. `identity` is `AshTypst.Wasm.identity/0` of the server:
// if the module is of another build, `init` fails and the worker does
// nothing.
//
// `files` sets the text of each file in `files` (an object of path to text)
// and removes each path in `removed`. `entry` sets the main file.
//
// `fonts` replaces the list of the fonts (`AshTypst.Wasm.fonts/1` of the
// server): an array of family names or `{family, style, weight, stretch,
// math, variable, axes}`. `init` takes it too (optional). The completion
// and the hover of `text(font: ...)` use it, and `syntax_errors` warns on
// a literal family of `text` that is not in it. Without a list, there are
// no font completions and no font warnings.

let Analyzer = null
let analyzer = null

const handlers = {
  async init({ glue, wasm, identity, fonts }) {
    const module = await import(glue)
    await module.default({ module_or_path: wasm })
    Analyzer = module.Analyzer

    const build = Analyzer.build_info()

    if (identity && (build.version !== identity.version || build.typst !== identity.typst)) {
      throw new Error(
        `The Typst editing module is version ${build.version} (Typst ${build.typst}), ` +
          `the server is version ${identity.version} (Typst ${identity.typst}). ` +
          `Run mix ash_typst.wasm.install.`,
      )
    }

    analyzer = new Analyzer()
    if (fonts) analyzer.set_fonts(fonts)
    return { build }
  },

  fonts({ fonts }) {
    analyzer.set_fonts(fonts || [])
    return true
  },

  entry({ path }) {
    analyzer.set_entry(path)
    return true
  },

  files({ files, removed }) {
    for (const path of removed || []) analyzer.remove(path)
    for (const [path, text] of Object.entries(files || {})) analyzer.set_file(path, text)
    return true
  },

  highlight({ path }) {
    return analyzer.highlight(path)
  },

  syntax_errors({ path }) {
    return analyzer.syntax_errors(path)
  },

  autocomplete({ path, cursor, explicit }) {
    return analyzer.autocomplete(path, cursor, Boolean(explicit))
  },

  tooltip({ path, cursor }) {
    return analyzer.tooltip(path, cursor)
  },

  definition({ path, cursor }) {
    return analyzer.definition(path, cursor)
  },
}

self.onmessage = async ({ data }) => {
  const { id, type, ...args } = data

  try {
    const handler = handlers[type]
    if (!handler) throw new Error(`Unknown request: ${type}`)
    if (type !== "init" && !analyzer) throw new Error("The Typst editing module is not ready.")
    self.postMessage({ id, result: await handler(args) })
  } catch (error) {
    self.postMessage({ id, error: String((error && error.message) || error) })
  }
}
