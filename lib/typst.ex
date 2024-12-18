defmodule Typst do
  @moduledoc """
  Documentation for `Typst`.
  """

  def preview(markup) do
    case Typst.NIF.preview(markup) do
      {:error, error} -> {:error, error}
      {preview, warnings} -> {:ok, {preview, trim_warnings(warnings)}}
    end
  end

  def export_pdf(markup) do
    case Typst.NIF.export_pdf(markup) do
      {:error, error} -> {:error, error}
      {pdf, warnings} -> {:ok, {pdf, trim_warnings(warnings)}}
    end
  end

  def font_families(), do: Typst.NIF.font_families()

  defp trim_warnings(warnings) do
    case String.trim(warnings) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
