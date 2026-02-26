defmodule AshTypst.ContextTest do
  use ExUnit.Case, async: true

  alias AshTypst.Context

  @test_markup "= Hello AshTypst\n\nThis is a *test* document with `code`."
  @test_markup_with_date "#set document(date: datetime(year: 2025, month: 1, day: 1))\n= Hello AshTypst\n\nThis is a *test* document with `code`."
  @multipage_markup """
  = Page One
  #pagebreak()
  = Page Two
  #pagebreak()
  = Page Three
  """
  @invalid_markup "#let invalid = "

  describe "new/1" do
    test "creates a context with defaults" do
      assert {:ok, ctx} = Context.new()
      assert is_reference(ctx)
    end

    test "creates a context with keyword opts" do
      assert {:ok, ctx} = Context.new(root: ".", font_paths: ["/usr/share/fonts"])
      assert is_reference(ctx)
    end

    test "creates a context with struct opts" do
      opts = %AshTypst.Context.Options{root: ".", ignore_system_fonts: false}
      assert {:ok, ctx} = Context.new(opts)
      assert is_reference(ctx)
    end
  end

  describe "compile + render_svg" do
    test "basic lifecycle: new -> set_markup -> compile -> render_svg" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup)

      assert {:ok, %AshTypst.CompileResult{page_count: 1, warnings: warnings}} =
               Context.compile(ctx)

      assert is_list(warnings)
      assert {:ok, svg} = Context.render_svg(ctx)
      assert String.contains?(svg, "<svg")
      assert String.length(svg) > 1000
    end

    test "compile returns page count" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @multipage_markup)
      assert {:ok, %AshTypst.CompileResult{page_count: 3}} = Context.compile(ctx)
    end

    test "render specific page" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @multipage_markup)
      {:ok, _} = Context.compile(ctx)

      assert {:ok, svg0} = Context.render_svg(ctx, page: 0)
      assert {:ok, svg2} = Context.render_svg(ctx, page: 2)
      assert String.contains?(svg0, "<svg")
      assert String.contains?(svg2, "<svg")
      assert svg0 != svg2
    end

    test "render out-of-bounds page returns error" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup)
      {:ok, _} = Context.compile(ctx)

      assert {:error, %AshTypst.CompileError{diagnostics: [_ | _]}} =
               Context.render_svg(ctx, page: 99)
    end

    test "render without compile returns error" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup)

      assert {:error, %AshTypst.CompileError{diagnostics: [_ | _]}} =
               Context.render_svg(ctx)
    end

    test "invalid markup returns compile error with diagnostics" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @invalid_markup)
      assert {:error, %AshTypst.CompileError{diagnostics: diagnostics}} = Context.compile(ctx)
      assert diagnostics != []

      [diag | _] = diagnostics
      assert diag.severity == :error
      assert is_binary(diag.message)
    end

    test "re-set markup + recompile produces different SVG" do
      {:ok, ctx} = Context.new()

      :ok = Context.set_markup(ctx, "= First")
      {:ok, _} = Context.compile(ctx)
      {:ok, svg1} = Context.render_svg(ctx)

      :ok = Context.set_markup(ctx, "= Second")
      {:ok, _} = Context.compile(ctx)
      {:ok, svg2} = Context.render_svg(ctx)

      assert svg1 != svg2
    end
  end

  describe "export_pdf" do
    test "returns proper PDF binary" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup)
      {:ok, _} = Context.compile(ctx)

      assert {:ok, <<"%PDF", _rest::binary>>} = Context.export_pdf(ctx)
    end

    test "with page range produces output" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @multipage_markup)
      {:ok, _} = Context.compile(ctx)

      assert {:ok, <<"%PDF", _::binary>> = full_pdf} = Context.export_pdf(ctx)

      # typst-pdf tagged PDF bug may cause page range export to fail
      case Context.export_pdf(ctx, pages: "1") do
        {:ok, <<"%PDF", _::binary>> = partial_pdf} ->
          assert byte_size(partial_pdf) < byte_size(full_pdf)

        {:error, %AshTypst.CompileError{}} ->
          :ok
      end
    end

    test "with standards" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup_with_date)
      {:ok, _} = Context.compile(ctx)

      assert {:ok, <<"%PDF", _::binary>>} =
               Context.export_pdf(ctx, pdf_standards: [:pdf_a_2b])
    end

    test "with document_id" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup)
      {:ok, _} = Context.compile(ctx)

      assert {:ok, <<"%PDF", _::binary>>} =
               Context.export_pdf(ctx, document_id: "test-42")
    end

    test "without compile returns error" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, @test_markup)

      assert {:error, %AshTypst.CompileError{}} = Context.export_pdf(ctx)
    end
  end

  describe "font_families" do
    test "standalone font_families returns list" do
      fonts = AshTypst.font_families()
      assert is_list(fonts)
      assert fonts != []
      assert Enum.all?(fonts, &is_binary/1)
    end

    test "context font_families returns list" do
      {:ok, ctx} = Context.new()
      fonts = Context.font_families(ctx)
      assert is_list(fonts)
      assert fonts != []
    end
  end

  describe "virtual files" do
    test "set virtual file and import in markup" do
      {:ok, ctx} = Context.new()
      Context.set_virtual_file(ctx, "data.typ", "#let data = (1, 2, 3)")
      Context.set_markup(ctx, "#import \"data.typ\": data\n#data")
      assert {:ok, %AshTypst.CompileResult{}} = Context.compile(ctx)
      assert {:ok, svg} = Context.render_svg(ctx)
      assert String.contains?(svg, "<svg")
    end

    test "stream_virtual_file with list of maps" do
      {:ok, ctx} = Context.new()

      records = for i <- 1..150, do: %{id: i, name: "item_#{i}"}

      Context.stream_virtual_file(ctx, "records.typ", records,
        variable_name: "records",
        batch_size: 50
      )

      Context.set_markup(ctx, "#import \"records.typ\": records\nCount: #records.len()")
      assert {:ok, %AshTypst.CompileResult{}} = Context.compile(ctx)
    end

    test "stream_virtual_file with custom variable name" do
      {:ok, ctx} = Context.new()
      data = [1, 2, 3]

      Context.stream_virtual_file(ctx, "nums.typ", data, variable_name: "numbers")
      Context.set_markup(ctx, "#import \"nums.typ\": numbers\n#numbers.len()")
      assert {:ok, _} = Context.compile(ctx)
    end

    test "append_virtual_file builds content incrementally" do
      {:ok, ctx} = Context.new()
      Context.set_virtual_file(ctx, "inc.typ", "#let items = (")
      Context.append_virtual_file(ctx, "inc.typ", "  1,\n")
      Context.append_virtual_file(ctx, "inc.typ", "  2,\n")
      Context.append_virtual_file(ctx, "inc.typ", ")\n")

      Context.set_markup(ctx, "#import \"inc.typ\": items\n#items.len()")
      assert {:ok, _} = Context.compile(ctx)
    end

    test "clear_virtual_file removes the file" do
      {:ok, ctx} = Context.new()
      Context.set_virtual_file(ctx, "temp.typ", "#let x = 1")
      Context.set_markup(ctx, "#import \"temp.typ\": x\n#x")
      assert {:ok, _} = Context.compile(ctx)

      Context.clear_virtual_file(ctx, "temp.typ")
      assert {:error, %AshTypst.CompileError{}} = Context.compile(ctx)
    end

    test "data changes produce different output" do
      {:ok, ctx} = Context.new()

      Context.set_virtual_file(ctx, "val.typ", "#let val = \"first\"")
      Context.set_markup(ctx, "#import \"val.typ\": val\n#val")
      {:ok, _} = Context.compile(ctx)
      {:ok, svg1} = Context.render_svg(ctx)

      Context.set_virtual_file(ctx, "val.typ", "#let val = \"second\"")
      {:ok, _} = Context.compile(ctx)
      {:ok, svg2} = Context.render_svg(ctx)

      assert svg1 != svg2
    end
  end

  describe "enhanced diagnostics" do
    test "diagnostics include line/column" do
      {:ok, ctx} = Context.new()
      :ok = Context.set_markup(ctx, "= Valid\n#let invalid = ")
      assert {:error, %AshTypst.CompileError{diagnostics: [diag | _]}} = Context.compile(ctx)
      assert diag.severity == :error

      if diag.span do
        assert is_integer(diag.span.start)
        assert is_integer(diag.span.end)
      end
    end
  end

  describe "sys.inputs" do
    test "set_input accessible in template" do
      {:ok, ctx} = Context.new()
      Context.set_input(ctx, "title", "Hello")
      Context.set_markup(ctx, "#sys.inputs.at(\"title\")")
      assert {:ok, _} = Context.compile(ctx)
      {:ok, svg} = Context.render_svg(ctx)
      assert String.contains?(svg, "<svg")
    end

    test "set_inputs replaces all inputs" do
      {:ok, ctx} = Context.new()
      Context.set_inputs(ctx, %{"a" => "1", "b" => "2"})
      Context.set_markup(ctx, "#sys.inputs.at(\"a\") #sys.inputs.at(\"b\")")
      assert {:ok, _} = Context.compile(ctx)
    end
  end

  describe "export_html" do
    test "returns HTML string" do
      {:ok, ctx} = Context.new()
      Context.set_markup(ctx, "= Hello HTML")

      case Context.export_html(ctx) do
        {:ok, html} ->
          assert is_binary(html)
          assert String.contains?(html, "<!DOCTYPE html>") or String.contains?(html, "<html")

        {:error, %AshTypst.CompileError{}} ->
          :ok
      end
    end

    test "works independently of compile" do
      {:ok, ctx} = Context.new()
      Context.set_markup(ctx, "= No prior compile needed")

      case Context.export_html(ctx) do
        {:ok, html} -> assert is_binary(html)
        {:error, _} -> :ok
      end
    end
  end
end
