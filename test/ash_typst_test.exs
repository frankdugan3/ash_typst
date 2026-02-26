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
end
