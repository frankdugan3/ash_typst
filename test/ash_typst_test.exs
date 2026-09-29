defmodule AshTypstTest do
  use ExUnit.Case, async: true

  describe "font_families/1" do
    test "returns system fonts by default" do
      fonts = AshTypst.font_families()
      assert is_list(fonts)
      assert fonts != []
      assert Enum.all?(fonts, &is_binary/1)
    end

    test "returns fonts with custom paths" do
      opts = %AshTypst.FontOptions{font_paths: ["/usr/share/fonts"]}
      fonts = AshTypst.font_families(opts)
      assert is_list(fonts)
      assert fonts != []
    end

    test "ignores system fonts when requested" do
      opts = %AshTypst.FontOptions{ignore_system_fonts: true}
      fonts = AshTypst.font_families(opts)
      assert is_list(fonts)
    end
  end

  describe "evict_cache/1" do
    test "evicts the memoization cache without affecting later compiles" do
      assert {:ok, ctx} = AshTypst.Context.new()
      :ok = AshTypst.Context.set_markup(ctx, "= Before\n#pagebreak()\n= Eviction")
      assert {:ok, %{page_count: 2}} = AshTypst.Context.compile(ctx)

      assert :ok = AshTypst.evict_cache()
      assert {:ok, %{page_count: 2}} = AshTypst.Context.compile(ctx)

      assert :ok = AshTypst.evict_cache(10)
      assert {:ok, pdf} = AshTypst.Context.export_pdf(ctx)
      assert <<"%PDF-", _rest::binary>> = pdf
    end

    test "rejects a negative max age" do
      assert_raise FunctionClauseError, fn -> AshTypst.evict_cache(-1) end
    end
  end
end
