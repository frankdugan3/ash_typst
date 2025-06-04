defmodule AshTypst.NIF do
  @moduledoc false
  use Rustler, otp_app: :ash_typst, crate: :typst_nif

  def preview(_typst_document, _opts), do: :erlang.nif_error(:not_loaded)
  def export_pdf(_typst_document, _opts), do: :erlang.nif_error(:not_loaded)
  def font_families(_opts), do: :erlang.nif_error(:not_loaded)
end
