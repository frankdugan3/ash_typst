defmodule AshTypst.NIF do
  @moduledoc false

  use RustlerPrecompiled,
    otp_app: :ash_typst,
    crate: "typst_nif",
    base_url:
      "https://github.com/frankdugan3/ash_typst/releases/download/v#{Mix.Project.config()[:version]}",
    version: Mix.Project.config()[:version],
    nif_versions: ["2.15", "2.16", "2.17"],
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

  def context_new(_opts), do: :erlang.nif_error(:not_loaded)
  def context_set_markup(_ctx, _markup), do: :erlang.nif_error(:not_loaded)
  def context_compile(_ctx), do: :erlang.nif_error(:not_loaded)
  def context_render_svg(_ctx, _page), do: :erlang.nif_error(:not_loaded)
  def context_export_pdf(_ctx, _opts), do: :erlang.nif_error(:not_loaded)
  def context_font_families(_ctx), do: :erlang.nif_error(:not_loaded)
  def context_set_virtual_file(_ctx, _path, _content), do: :erlang.nif_error(:not_loaded)
  def context_append_virtual_file(_ctx, _path, _chunk), do: :erlang.nif_error(:not_loaded)
  def context_clear_virtual_file(_ctx, _path), do: :erlang.nif_error(:not_loaded)
  def context_set_input(_ctx, _key, _value), do: :erlang.nif_error(:not_loaded)
  def context_set_inputs(_ctx, _inputs), do: :erlang.nif_error(:not_loaded)
  def context_export_html(_ctx), do: :erlang.nif_error(:not_loaded)
  def font_families(_opts), do: :erlang.nif_error(:not_loaded)
end
