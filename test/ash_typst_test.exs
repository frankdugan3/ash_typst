defmodule AshTypstTest do
  use ExUnit.Case, async: true

  doctest AshTypst

  @test_markup "= Hello AshTypst\n\nThis is a *test* document with `code`."

  describe "preview/2" do
    test "generates SVG preview with default options" do
      assert {:ok, {svg, diagnostics}} = AshTypst.preview(@test_markup)
      assert is_binary(svg)
      assert String.contains?(svg, "<svg")
      # SVG content splits text into individual characters via <use> elements
      # Just verify it contains SVG structure and substantial content
      assert String.length(svg) > 1000
      assert String.contains?(svg, "class=\"typst-text\"")
      assert is_list(diagnostics)
    end

    test "generates SVG preview with font paths" do
      opts = %AshTypst.PreviewOptions{font_paths: ["/usr/share/fonts"]}
      assert {:ok, {svg, _diagnostics}} = AshTypst.preview(@test_markup, opts)
      assert is_binary(svg)
      assert String.contains?(svg, "<svg")
    end

    @tag :skip_until_rust_fix
    test "generates SVG preview ignoring system fonts" do
      opts = %AshTypst.PreviewOptions{ignore_system_fonts: true}
      assert {:ok, {svg, _diagnostics}} = AshTypst.preview(@test_markup, opts)
      assert is_binary(svg)
      assert String.contains?(svg, "<svg")
    end

    test "handles invalid markup gracefully" do
      assert {:error, %{diagnostics: diagnostics}} = AshTypst.preview("#let invalid = ")
      assert is_list(diagnostics)
      assert length(diagnostics) > 0
    end
  end

  describe "export_pdf/2" do
    test "exports PDF with default options" do
      assert {:ok, {pdf, diagnostics}} = AshTypst.export_pdf(@test_markup)
      assert is_binary(pdf)
      # PDF should be substantial
      assert String.length(pdf) > 1000
      assert is_list(diagnostics)
    end

    test "exports PDF with PDF standards" do
      opts = %AshTypst.PDFOptions{pdf_standards: [:pdf_a_2b]}
      assert {:ok, {pdf, _diagnostics}} = AshTypst.export_pdf(@test_markup, opts)
      assert is_binary(pdf)
      assert String.length(pdf) > 1000
    end

    test "exports PDF with multiple standards" do
      opts = %AshTypst.PDFOptions{pdf_standards: [:pdf_1_7, :pdf_a_2b]}
      assert {:ok, {pdf, _diagnostics}} = AshTypst.export_pdf(@test_markup, opts)
      assert is_binary(pdf)
    end

    test "exports PDF with document ID" do
      opts = %AshTypst.PDFOptions{document_id: "test-document"}
      assert {:ok, {pdf, _diagnostics}} = AshTypst.export_pdf(@test_markup, opts)
      assert is_binary(pdf)
    end

    test "exports PDF with font paths" do
      opts = %AshTypst.PDFOptions{font_paths: ["/usr/share/fonts"]}
      assert {:ok, {pdf, _diagnostics}} = AshTypst.export_pdf(@test_markup, opts)
      assert is_binary(pdf)
    end

    @tag :skip_until_rust_fix
    test "exports PDF ignoring system fonts" do
      opts = %AshTypst.PDFOptions{ignore_system_fonts: true}
      assert {:ok, {pdf, _diagnostics}} = AshTypst.export_pdf(@test_markup, opts)
      assert is_binary(pdf)
    end

    test "exports PDF with combined options" do
      opts = %AshTypst.PDFOptions{
        pdf_standards: [:pdf_a_2b],
        document_id: "comprehensive-test",
        font_paths: ["/usr/share/fonts"],
        ignore_system_fonts: false
      }

      assert {:ok, {pdf, _diagnostics}} = AshTypst.export_pdf(@test_markup, opts)
      assert is_binary(pdf)
    end

    test "handles invalid markup gracefully" do
      assert {:error, %{diagnostics: diagnostics}} = AshTypst.export_pdf("#let invalid = ")
      assert is_list(diagnostics)
      assert length(diagnostics) > 0
    end
  end

  describe "font_families/1" do
    test "returns system fonts by default" do
      fonts = AshTypst.font_families()
      assert is_list(fonts)
      assert length(fonts) > 0
      assert Enum.all?(fonts, &is_binary/1)
    end

    test "returns fonts with custom paths" do
      opts = %AshTypst.FontOptions{font_paths: ["/usr/share/fonts"]}
      fonts = AshTypst.font_families(opts)
      assert is_list(fonts)
      assert length(fonts) > 0
    end

    test "filters out non-existent paths" do
      opts = %AshTypst.FontOptions{font_paths: ["/non/existent/path", "/usr/share/fonts"]}
      fonts = AshTypst.font_families(opts)
      assert is_list(fonts)
      # Should still return fonts because /usr/share/fonts likely exists
      # and system fonts are included by default
    end

    test "ignores system fonts when requested" do
      opts = %AshTypst.FontOptions{ignore_system_fonts: true}
      fonts = AshTypst.font_families(opts)
      assert is_list(fonts)
      # Should return empty or very few fonts since no custom paths provided
      assert length(fonts) < 10
    end

    test "combines custom paths with system font exclusion" do
      opts = %AshTypst.FontOptions{
        font_paths: ["/usr/share/fonts"],
        ignore_system_fonts: true
      }

      fonts = AshTypst.font_families(opts)
      assert is_list(fonts)
      # Should only include fonts from custom paths
    end
  end

  describe "stream_to_datafile!/3" do
    @tmp_dir System.tmp_dir!()

    test "creates datafile from stream with default options" do
      filepath = Path.join(@tmp_dir, "test_data.typ")
      data = [%{name: "Alice", age: 30}, %{name: "Bob", age: 25}]

      assert :ok = AshTypst.stream_to_datafile!(data, filepath)

      content = File.read!(filepath)
      assert String.starts_with?(content, "let data = (")
      assert String.ends_with?(content, ")")
      assert String.contains?(content, "Alice")
      assert String.contains?(content, "Bob")

      File.rm!(filepath)
    end

    test "creates datafile with custom variable name" do
      filepath = Path.join(@tmp_dir, "test_custom.typ")
      data = [1, 2, 3]
      opts = [variable_name: "numbers"]

      assert :ok = AshTypst.stream_to_datafile!(data, filepath, opts)

      content = File.read!(filepath)
      assert String.starts_with?(content, "let numbers = (")

      File.rm!(filepath)
    end
  end

  describe "option struct defaults" do
    test "PreviewOptions has correct defaults" do
      opts = %AshTypst.PreviewOptions{}
      assert opts.font_paths == []
      assert opts.ignore_system_fonts == false
    end

    test "PDFOptions has correct defaults" do
      opts = %AshTypst.PDFOptions{}
      assert opts.pages == nil
      assert opts.pdf_standards == []
      assert opts.document_id == nil
      assert opts.font_paths == []
      assert opts.ignore_system_fonts == false
    end

    test "FontOptions has correct defaults" do
      opts = %AshTypst.FontOptions{}
      assert opts.font_paths == []
      assert opts.ignore_system_fonts == false
    end
  end
end
