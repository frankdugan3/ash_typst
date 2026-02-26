defmodule AshTypst.SigilTest do
  use ExUnit.Case, async: true

  import AshTypst.Sigil

  describe "~TYPST sigil" do
    test "returns plain string" do
      assert ~TYPST"= Hello" == "= Hello"
    end

    test "preserves # characters literally" do
      assert ~TYPST"#let x = 1" == "#let x = 1"
    end

    test "works with heredoc" do
      markup = ~TYPST"""
      = Title
      #import "data.typ": record
      *#record.name*
      """

      assert markup == "= Title\n#import \"data.typ\": record\n*#record.name*\n"
    end

    test "preserves Typst expressions without Elixir interpolation" do
      markup = ~TYPST"#{1 + 2} is Typst code"
      assert markup == "\#{1 + 2} is Typst code"
    end

    test "works with pipe delimiters" do
      assert ~TYPST|#set page(width: 3in)| == "#set page(width: 3in)"
    end
  end
end
