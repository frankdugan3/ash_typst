defmodule AshTypst do
  @moduledoc """
  Precompiled Rust NIFs for rendering [Typst](https://typst.app) documents from Elixir.

  All rendering goes through a persistent `AshTypst.Context`, which loads fonts
  once and keeps the compiled document in memory so you can render pages, export
  PDFs, or re-compile after a markup change without repeating expensive setup.

  ## Architecture

  ```mermaid
  graph TB
    subgraph Elixir
      direction LR
      C[AshTypst.Code] -->|encode| A[AshTypst.Context] -->|NIF calls| N[AshTypst.NIF]
    end

    N --> W
    N --> VF
    N --> IN
    N --> F

    subgraph "Rust -- TypstContext resource"
      subgraph "SystemWorld (persistent)"
        direction LR
        W[Markup]
        VF[Virtual Files]
        IN[sys.inputs]
        F[Fonts + FontBook]
        FS["File Slots -- disk cache"]
      end

      W  -->|compile| PD
      VF -->|import| PD
      IN -->|sys.inputs| PD
      F  -->|font resolve| PD
      FS -->|import pkg| PD

      subgraph "Compiled Output"
        PD["PagedDocument (cached)"]
      end

      PD -->|render_svg| SVG[SVG string]
      PD -->|export_pdf| PDF[PDF binary]
      W  -->|export_html| HTML[HTML string]
    end
  ```

  **Key points:**

  - The `TypstContext` is a Rust NIF resource held as an opaque reference in Elixir.
  - Fonts are scanned once at context creation and reused for every compile.
  - `compile/1` stores a `PagedDocument`; `render_svg/2` and `export_pdf/2` read from it without recompiling.
  - `export_html/1` performs its own compilation (HTML uses a different document type internally).
  - Virtual files and `sys.inputs` persist across compiles until explicitly changed.

  ## Quick start

      # Create a context (fonts scanned once)
      {:ok, ctx} = AshTypst.Context.new(root: "/path/to/templates")

      # Set markup and compile
      :ok = AshTypst.Context.set_markup(ctx, "= Hello World")
      {:ok, %AshTypst.CompileResult{page_count: 1}} = AshTypst.Context.compile(ctx)

      # Render any page as SVG
      {:ok, svg} = AshTypst.Context.render_svg(ctx, page: 0)

      # Export the full document as PDF
      {:ok, pdf_binary} = AshTypst.Context.export_pdf(ctx)

  ## Data injection

  You can feed Elixir data into templates in two ways:

  ### Virtual files

  Create in-memory `.typ` files that your template can `#import`:

      AshTypst.Context.set_virtual_file(ctx, "data.typ", ~s(#let title = "Q4 Report"))
      AshTypst.Context.set_markup(ctx, ~s(#import "data.typ": title\\n= \\#title))

  For large datasets, stream records in batches to keep Elixir memory flat:

      AshTypst.Context.stream_virtual_file(ctx, "rows.typ", records_stream,
        variable_name: "rows",
        context: %{timezone: "America/New_York"}
      )

  ### `sys.inputs`

  Pass simple string key/value pairs accessible via `#sys.inputs` in templates:

      AshTypst.Context.set_inputs(ctx, %{"theme" => "dark", "locale" => "en"})

  ## Data encoding

  The `AshTypst.Code` protocol converts Elixir values to Typst source syntax.
  It handles maps, lists, dates, decimals, Ash resources, and more.
  See `AshTypst.Code.encode/2` for the full type mapping.

  ## Live editing

  The context is designed for iterative workflows. Only the markup (or virtual
  file) that changed needs to be re-set before re-compiling; fonts and other
  state stay hot:

      :ok = AshTypst.Context.set_markup(ctx, updated_template)
      {:ok, _} = AshTypst.Context.compile(ctx)
      {:ok, svg} = AshTypst.Context.render_svg(ctx, page: current_page)
  """

  @doc """
  List all font families available to Typst.

  This is a standalone operation that does not require a context.
  For fonts loaded in a context, use `AshTypst.Context.font_families/1`.
  """
  @spec font_families(AshTypst.FontOptions.t()) :: [String.t()]
  def font_families(%AshTypst.FontOptions{} = opts \\ %AshTypst.FontOptions{}) do
    AshTypst.NIF.font_families(opts)
  end
end
