defmodule AshTypst.Context do
  @moduledoc """
  Persistent Typst rendering context.

  A context wraps a Rust-side `SystemWorld` that keeps fonts, virtual files,
  and the compiled document in memory. The typical lifecycle is:

  1. `new/1` — create a context (scans fonts, sets root path)
  2. `set_markup/2` — load a Typst template
  3. Optionally inject data via `set_virtual_file/3`, `stream_virtual_file/4`, or `set_inputs/2`
  4. `compile/1` — compile the markup into a paged document
  5. `render_svg/2` or `export_pdf/2` — render output from the compiled document
     (`export_html/2` and `export_bundle/2` compile on their own)

  Steps 2-5 can be repeated without re-creating the context. Fonts and
  virtual files persist until explicitly changed.

  ## Thread safety

  Each function acquires internal locks, so a single context can be shared
  across processes. However, concurrent `compile` and `set_markup` calls on
  the same context will serialize — design your pipeline accordingly.
  """

  alias AshTypst.NIF

  @doc """
  Create a new context.

  Fonts are scanned once during creation and reused across all operations.

  ## Options

    * `:root` — directory templates may read real files from (imports,
      images, data files). Defaults to `nil`, which disables filesystem
      access entirely: only virtual files and packages are available, and
      any other file reference fails to compile. Set this explicitly to
      let templates read from disk. Access is sandboxed to the root —
      paths cannot escape it (e.g. via `..`).
    * `:font_paths` — additional font directories to search
    * `:ignore_system_fonts` — skip system fonts (default `false`)

  > #### Security {: .warning}
  >
  > Everything under `:root` becomes readable by any template compiled in
  > this context. Point it at a directory containing only template assets —
  > never at `"."` or a directory with secrets (`.env`, config files, etc.).
  """

  def new(opts \\ [])

  def new(%AshTypst.Context.Options{} = opts) do
    {:ok, NIF.context_new(opts)}
  end

  def new(opts) when is_list(opts) do
    new(struct!(AshTypst.Context.Options, opts))
  end

  @doc "Set the main Typst markup. Invalidates any compiled document."

  def set_markup(ctx, markup) when is_binary(markup) do
    NIF.context_set_markup(ctx, markup)
  end

  @doc """
  Compile the current markup.

  Returns `{:ok, %CompileResult{}}` with the page count and warnings,
  or `{:error, %CompileError{}}` with diagnostics.
  """

  def compile(ctx) do
    NIF.context_compile(ctx)
  end

  @doc """
  Render a page of the compiled document as SVG.

  ## Options

    * `:page` — zero-indexed page number (default `0`)
    * `:pretty` — format the SVG in a human-readable way (default `false`, i.e.
      minified)
    * `:render_bleed` — expand the rendered area beyond the page bounds to
      include bleed margins, useful when preparing documents for print
      (default `false`)
  """

  def render_svg(ctx, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    pretty = Keyword.get(opts, :pretty, false)
    render_bleed = Keyword.get(opts, :render_bleed, false)
    NIF.context_render_svg(ctx, page, pretty, render_bleed)
  end

  @doc """
  Export the compiled document as a PDF binary.

  ## Options

    * `:pages` — page range string like `"1-3,5,7-9"` (1-indexed)
    * `:pdf_standards` — list of standards, e.g. `[:pdf_a_2b]`
    * `:document_id` — stable identifier for caching
  """

  def export_pdf(ctx, opts \\ [])

  def export_pdf(ctx, %AshTypst.PDFOptions{} = opts) do
    NIF.context_export_pdf(ctx, opts)
  end

  def export_pdf(ctx, opts) when is_list(opts) do
    export_pdf(ctx, struct!(AshTypst.PDFOptions, opts))
  end

  @doc "List font families available in this context."

  def font_families(ctx) do
    NIF.context_font_families(ctx)
  end

  @doc "Set (or overwrite) a virtual file with text content. Invalidates the compiled document."

  def set_virtual_file(ctx, path, content) when is_binary(path) and is_binary(content) do
    NIF.context_set_virtual_file(ctx, path, content)
  end

  @doc """
  Set (or overwrite) a virtual file with raw binary content. Invalidates the compiled document.

  Use this for non-text files like images (PNG, SVG) that Typst reads via
  `#image(read("name", encoding: none))`.
  """

  def set_virtual_file_binary(ctx, path, content) when is_binary(path) and is_binary(content) do
    NIF.context_set_virtual_file_binary(ctx, path, content)
  end

  @doc """
  Append a chunk to a virtual file (creates it if new).

  Does **not** invalidate the compiled document — call `compile/1`
  after streaming is complete.
  """

  def append_virtual_file(ctx, path, chunk) when is_binary(path) and is_binary(chunk) do
    NIF.context_append_virtual_file(ctx, path, chunk)
  end

  @doc "Remove a virtual file. Invalidates the compiled document."

  def clear_virtual_file(ctx, path) when is_binary(path) do
    NIF.context_clear_virtual_file(ctx, path)
  end

  @doc """
  Stream an Elixir enumerable into a virtual file as a Typst array.

  Each element is encoded via `AshTypst.Code.encode/2` and batched
  to Rust for memory efficiency.

  ## Options

    * `:variable_name` — the `#let` binding name (default `"data"`)
    * `:context` — encoding context passed to `AshTypst.Code.encode/2`
    * `:batch_size` — records per NIF call (default `100`)
  """

  def stream_virtual_file(ctx, path, stream, opts \\ []) do
    variable_name = opts[:variable_name] || "data"
    context = opts[:context] || %{}
    batch_size = opts[:batch_size] || 100

    NIF.context_set_virtual_file(ctx, path, "#let #{variable_name} = (\n")

    stream
    |> Stream.chunk_every(batch_size)
    |> Enum.each(fn batch ->
      chunk =
        Enum.map_join(batch, fn item ->
          "  " <> AshTypst.Code.encode(item, context) <> ",\n"
        end)

      NIF.context_append_virtual_file(ctx, path, chunk)
    end)

    NIF.context_append_virtual_file(ctx, path, ")\n")
  end

  @doc "Set a single `sys.inputs` key/value pair."

  def set_input(ctx, key, value) when is_binary(key) and is_binary(value) do
    NIF.context_set_input(ctx, key, value)
  end

  @doc "Replace all `sys.inputs` with the given map of string keys/values."

  def set_inputs(ctx, inputs) when is_map(inputs) do
    NIF.context_set_inputs(ctx, inputs)
  end

  @doc """
  Export the document as HTML.

  Performs its own compilation (separate from `compile/1`).

  ## Options

    * `:pretty` — format the HTML in a human-readable way (default `false`,
      i.e. minified)
  """

  def export_html(ctx, opts \\ []) do
    pretty = Keyword.get(opts, :pretty, false)
    NIF.context_export_html(ctx, pretty)
  end

  @doc """
  Export the document as a multi-file bundle.

  The `bundle` target lets a single Typst project emit multiple documents and
  assets. The template declares its outputs with top-level [`document`] and
  [`asset`] elements. Each takes the destination path as its first positional
  argument, for example:

  ```typ
  #document("index.html", title: [Home])[
    = Home
    See the #link("about.html")[about page].
  ]
  #document("about.html", title: [About])[= About]
  #asset("logo.svg", read("logo.svg", encoding: none))
  ```

  Performs its own compilation (separate from `compile/1`). Returns
  `{:ok, %AshTypst.BundleResult{}}` whose `files` is a map of relative path (no
  leading slash) to the rendered binary content, e.g. `%{"index.html" => "...",
  "about.html" => "..."}`, and whose `warnings` is a list of
  `AshTypst.Diagnostic` warnings.

  Documents within the bundle are exported according to their declared format
  (HTML, PDF, SVG, or PNG); assets are emitted verbatim.

  ## Options

    * `:pretty` — format HTML/SVG documents in a human-readable way (default
      `false`, i.e. minified)
    * `:render_bleed` — include bleed margins for SVG documents (default
      `false`)

  [`document`]: https://typst.app/docs/reference/model/document/
  [`asset`]: https://typst.app/docs/reference/data-loading/asset/
  """

  def export_bundle(ctx, opts \\ [])

  def export_bundle(ctx, %AshTypst.BundleOptions{} = opts) do
    NIF.context_export_bundle(ctx, opts)
  end

  def export_bundle(ctx, opts) when is_list(opts) do
    export_bundle(ctx, struct!(AshTypst.BundleOptions, opts))
  end
end
