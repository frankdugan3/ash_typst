defmodule Typst do
  @moduledoc """
  Documentation for `Typst`.
  """

  @doc """
  Stream an Elixir data source into a file, encoded into Typst code format.
  """
  def stream_to_datafile!(stream, filepath, opts \\ []) do
    variable_name = opts[:variable_name] || "data"
    context = opts[:context] || []

    File.write!(filepath, "let #{variable_name} = (\n")

    stream
    |> Stream.map(&("  " <> Typst.Code.encode(&1, context) <> ",\n"))
    |> Stream.into(File.stream!(filepath, [:append]))
    |> Stream.run()

    File.write!(filepath, ")", [:append])
  end

  @doc """
  Generate an SVG preview of the first page of a Typst document.
  """
  def preview(markup) do
    case Typst.NIF.preview(markup) do
      {:error, error} -> {:error, error}
      {preview, warnings} -> {:ok, {preview, trim_warnings(warnings)}}
    end
  end

  @doc """
  Compile a typst document into a PDF file.
  """
  def export_pdf(markup) do
    case Typst.NIF.export_pdf(markup) do
      {:error, error} -> {:error, error}
      {pdf, warnings} -> {:ok, {pdf, trim_warnings(warnings)}}
    end
  end

  @doc """
  List all fonts detected by Typst.
  """
  def font_families(), do: Typst.NIF.font_families()

  defp trim_warnings(warnings) do
    case String.trim(warnings) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
