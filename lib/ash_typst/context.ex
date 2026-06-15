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

    * `:root` — root path for template resolution (default `"."`)
    * `:font_paths` — additional font directories to search
    * `:ignore_system_fonts` — skip system fonts (default `false`)
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
  """

  def render_svg(ctx, opts \\ []) do
    page = Keyword.get(opts, :page, 0)
    NIF.context_render_svg(ctx, page)
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
  """

  def export_html(ctx) do
    NIF.context_export_html(ctx)
  end
end
