defmodule AshTypst do
  @moduledoc """
  Documentation for `AshTypst`.
  """

  alias __MODULE__.NIF

  @doc """
  Stream an Elixir data source into a file, encoded into Typst code format.
  """
  @spec stream_to_datafile!(Enumerable.t(), String.t(), keyword()) :: :ok
  def stream_to_datafile!(stream, filepath, opts \\ []) do
    variable_name = opts[:variable_name] || "data"
    context = opts[:context] || []

    File.write!(filepath, "let #{variable_name} = (\n")

    stream
    |> Stream.map(&("  " <> AshTypst.Code.encode(&1, context) <> ",\n"))
    |> Stream.into(File.stream!(filepath, [:append]))
    |> Stream.run()

    File.write!(filepath, ")", [:append])
  end

  defmodule PreviewOptions do
    @moduledoc """
    Options for SVG preview generation.
    """
    defstruct font_paths: [], ignore_system_fonts: false

    @type t :: %__MODULE__{
            font_paths: [String.t()],
            ignore_system_fonts: boolean()
          }
  end

  @doc """
  Generate an SVG preview of the first page of a Typst document.

  ## Options (PreviewOptions struct)

  - `:font_paths` - List of additional font directory paths to search
  - `:ignore_system_fonts` - Whether to ignore system fonts (default: false)

  ## Examples

      AshTypst.preview("#heading[Hello World]")
      # => {:ok, {svg_content, warnings}}

      AshTypst.preview("#heading[Hello World]", %AshTypst.PreviewOptions{font_paths: ["/path/to/fonts"]})
      # => {:ok, {svg_content, warnings}}

      AshTypst.preview("#heading[Hello World]", %AshTypst.PreviewOptions{ignore_system_fonts: true})
      # => {:ok, {svg_content, warnings}}

  """
  @spec preview(String.t(), PreviewOptions.t()) ::
          {:ok, {String.t(), String.t() | nil}} | {:error, String.t()}
  def preview(markup, %PreviewOptions{} = opts \\ %PreviewOptions{}) do
    case NIF.preview(markup, opts) do
      {:error, error} -> {:error, error}
      {preview, warnings} -> {:ok, {preview, trim_warnings(warnings)}}
    end
  end

  defmodule PDFOptions do
    @moduledoc """
    Options for PDF generation.
    """
    defstruct pages: nil,
              pdf_standards: [],
              document_id: nil,
              font_paths: [],
              ignore_system_fonts: false

    @type t :: %__MODULE__{
            pages: String.t() | nil,
            pdf_standards: [:pdf_1_7 | :pdf_a_2b | :pdf_a_3b],
            document_id: String.t() | nil,
            font_paths: [String.t()],
            ignore_system_fonts: boolean()
          }
  end

  @doc """
  Compile a typst document into a PDF file.

  ## Options (PDFOptions struct)

  - `:pages` - String specifying which pages to export (e.g., "1-5", "1,3,7")
  - `:pdf_standards` - List of PDF standard compliance (e.g., `[:pdf_1_7, :pdf_a_2b]`) (default: [])
  - `:document_id` - Custom document identifier for tracking/caching
  - `:font_paths` - List of additional font directory paths to search
  - `:ignore_system_fonts` - Whether to ignore system fonts (default: false)

  ## Examples

      AshTypst.export_pdf("#heading[Hello World]")
      # => {:ok, {pdf_binary, warnings}}

      AshTypst.export_pdf("#heading[Hello World]", %AshTypst.PDFOptions{pages: "1-5", pdf_standards: [:pdf_a_2b]})
      # => {:ok, {pdf_binary, warnings}}

      AshTypst.export_pdf("#heading[Hello World]", %AshTypst.PDFOptions{font_paths: ["/path/to/fonts"], ignore_system_fonts: true})
      # => {:ok, {pdf_binary, warnings}}

  """
  @spec export_pdf(String.t(), PDFOptions.t()) ::
          {:ok, {String.t(), String.t() | nil}} | {:error, String.t()}
  def export_pdf(markup, %PDFOptions{} = opts \\ %PDFOptions{}) do
    case NIF.export_pdf(markup, opts) do
      {:error, error} -> {:error, error}
      {pdf, warnings} -> {:ok, {pdf, trim_warnings(warnings)}}
    end
  end

  defmodule FontOptions do
    @moduledoc """
    Options for font operations.
    """
    defstruct font_paths: [], ignore_system_fonts: false

    @type t :: %__MODULE__{
            font_paths: [String.t()],
            ignore_system_fonts: boolean()
          }
  end

  @doc """
  List all fonts detected by Typst.

  ## Options (FontOptions struct)

  - `:font_paths` - List of additional font directory paths to search
  - `:ignore_system_fonts` - Whether to ignore system fonts (default: false)

  ## Examples

      AshTypst.font_families()
      # => ["Arial", "Times New Roman", ...]

      AshTypst.font_families(%AshTypst.FontOptions{font_paths: ["/path/to/custom/fonts"]})
      # => ["Arial", "Times New Roman", "Custom Font", ...]

      AshTypst.font_families(%AshTypst.FontOptions{ignore_system_fonts: true})
      # => []  # Only custom fonts if any

  """
  @spec font_families(FontOptions.t()) :: [String.t()]
  def font_families(%FontOptions{} = opts \\ %FontOptions{}) do
    NIF.font_families(opts)
  end

  defp trim_warnings(warnings) do
    case String.trim(warnings) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
