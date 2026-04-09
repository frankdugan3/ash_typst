defmodule AshTypst.NIF do
  @moduledoc false

  mode = if Mix.env() in [:dev, :test], do: :debug, else: :release

  use Rustler,
    otp_app: :ash_typst,
    crate: "typst_nif",
    mode: mode

  def context_new(_opts), do: :erlang.nif_error(:not_loaded)
  def context_set_markup(_ctx, _markup), do: :erlang.nif_error(:not_loaded)
  def context_compile(_ctx), do: :erlang.nif_error(:not_loaded)
  def context_render_svg(_ctx, _page), do: :erlang.nif_error(:not_loaded)
  def context_export_pdf(_ctx, _opts), do: :erlang.nif_error(:not_loaded)
  def context_font_families(_ctx), do: :erlang.nif_error(:not_loaded)
  def context_set_virtual_file(_ctx, _path, _content), do: :erlang.nif_error(:not_loaded)
  def context_set_virtual_file_binary(_ctx, _path, _content), do: :erlang.nif_error(:not_loaded)
  def context_append_virtual_file(_ctx, _path, _chunk), do: :erlang.nif_error(:not_loaded)
  def context_clear_virtual_file(_ctx, _path), do: :erlang.nif_error(:not_loaded)
  def context_set_input(_ctx, _key, _value), do: :erlang.nif_error(:not_loaded)
  def context_set_inputs(_ctx, _inputs), do: :erlang.nif_error(:not_loaded)
  def context_export_html(_ctx), do: :erlang.nif_error(:not_loaded)
  def font_families(_opts), do: :erlang.nif_error(:not_loaded)
end
