defmodule AshTypst.NIF do
  @moduledoc """
  Native interface functions for the Typst library.

  This module provides low-level NIF functions for interacting with the Rust Typst library.
  These functions are not intended for direct use - use the higher-level `AshTypst` module instead.
  """

  use RustlerPrecompiled,
    otp_app: :ash_typst,
    crate: "typst_nif",
    base_url:
      "https://github.com/frankdugan3/ash_typst/releases/download/v#{Mix.Project.config()[:version]}",
    version: Mix.Project.config()[:version],
    nif_versions: ["2.14", "2.15", "2.16", "2.17"],
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-apple-darwin
      x86_64-pc-windows-msvc
      x86_64-pc-windows-gnu
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    )

  @doc """
  Generate a preview of a Typst document.
  """
  @spec preview(String.t(), map()) :: {:ok, binary()} | {:error, String.t()}
  def preview(_typst_document, _opts), do: :erlang.nif_error(:not_loaded)

  @doc """
  Export a Typst document to PDF format.
  """
  @spec export_pdf(String.t(), map()) :: {:ok, binary()} | {:error, String.t()}
  def export_pdf(_typst_document, _opts), do: :erlang.nif_error(:not_loaded)

  @doc """
  Get available font families.
  """
  @spec font_families(map()) :: {:ok, [String.t()]} | {:error, String.t()}
  def font_families(_opts), do: :erlang.nif_error(:not_loaded)
end
