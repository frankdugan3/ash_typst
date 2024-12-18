defmodule Typst.NIF do
  @moduledoc false
  use Rustler, otp_app: :typst, crate: :typst_nif

  def preview(_typst_document), do: :erlang.nif_error(:not_loaded)
  def export_pdf(_typst_document), do: :erlang.nif_error(:not_loaded)
  def font_families(), do: :erlang.nif_error(:not_loaded)
end
