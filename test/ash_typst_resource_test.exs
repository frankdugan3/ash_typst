defmodule AshTypst.ResourceTest do
  use ExUnit.Case, async: true

  # --- Test Domain & Resources ---

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule InlineTemplateResource do
    use Ash.Resource,
      domain: AshTypst.ResourceTest.TestDomain,
      extensions: [AshTypst.Resource]

    typst do
      template :greeting do
        markup(~TYPST"""
        #import "data.typ": args
        = Hello #args.name
        """)
      end

      template :simple do
        markup("= Static Page")
      end

      render :render_greeting do
        template(:greeting)
        format(:pdf)

        argument :name, :string, allow_nil?: false
      end

      render :render_svg_greeting do
        template(:greeting)
        format(:svg)
        page 0

        argument :name, :string, allow_nil?: false
      end

      render :render_html_greeting do
        template(:greeting)
        format(:html)

        argument :name, :string, allow_nil?: false
      end

      render :render_simple do
        template(:simple)
        format(:pdf)
      end
    end
  end

  defmodule PdfOptionsResource do
    use Ash.Resource,
      domain: AshTypst.ResourceTest.TestDomain,
      extensions: [AshTypst.Resource]

    typst do
      template :doc do
        markup("#set document(date: datetime(year: 2026, month: 1, day: 1))\n= PDF Test")
      end

      render :render_pdf do
        template(:doc)
        format(:pdf)

        pdf_options do
          pdf_standards([:pdf_a_2b])
        end
      end
    end
  end

  # --- Tests ---

  describe "DSL compilation" do
    test "resource with inline template and render action compiles" do
      assert InlineTemplateResource.__info__(:module) == InlineTemplateResource
    end

    test "resource with pdf_options compiles" do
      assert PdfOptionsResource.__info__(:module) == PdfOptionsResource
    end

    test "templates are accessible via Info" do
      templates = AshTypst.Resource.Info.templates(InlineTemplateResource)
      assert length(templates) == 2

      assert {:ok, greeting} = AshTypst.Resource.Info.template(InlineTemplateResource, :greeting)
      assert greeting.name == :greeting
      assert greeting.markup =~ "Hello #args.name"

      assert {:ok, simple} = AshTypst.Resource.Info.template(InlineTemplateResource, :simple)
      assert simple.markup == "= Static Page"
    end

    test "template! raises for unknown template" do
      assert_raise ArgumentError, ~r/No template named :nonexistent/, fn ->
        AshTypst.Resource.Info.template!(InlineTemplateResource, :nonexistent)
      end
    end

    test "template/2 returns :error for unknown template" do
      assert :error = AshTypst.Resource.Info.template(InlineTemplateResource, :nonexistent)
    end

    test "typst section options are accessible via Info" do
      assert {:ok, "priv/typst"} = AshTypst.Resource.Info.typst_root(InlineTemplateResource)
      assert {:ok, []} = AshTypst.Resource.Info.typst_font_paths(InlineTemplateResource)

      assert {:ok, false} =
               AshTypst.Resource.Info.typst_ignore_system_fonts(InlineTemplateResource)
    end
  end

  describe "transformer" do
    test "render entities are transformed into generic actions" do
      actions = Ash.Resource.Info.actions(InlineTemplateResource)
      render_greeting = Enum.find(actions, &(&1.name == :render_greeting))

      assert render_greeting != nil
      assert %Ash.Resource.Actions.Action{} = render_greeting
      assert render_greeting.type == :action
      assert render_greeting.returns == AshTypst.Type.Document
      assert {AshTypst.Resource.Run, opts} = render_greeting.run
      assert opts[:template] == :greeting
      assert opts[:format] == :pdf
    end

    test "arguments are preserved on transformed action" do
      actions = Ash.Resource.Info.actions(InlineTemplateResource)
      render_greeting = Enum.find(actions, &(&1.name == :render_greeting))
      args = render_greeting.arguments

      assert length(args) == 1
      assert hd(args).name == :name
      assert hd(args).allow_nil? == false
    end

    test "svg action has page option" do
      actions = Ash.Resource.Info.actions(InlineTemplateResource)
      svg_action = Enum.find(actions, &(&1.name == :render_svg_greeting))

      assert {AshTypst.Resource.Run, opts} = svg_action.run
      assert opts[:page] == 0
      assert opts[:format] == :svg
    end

    test "pdf_options are included in run opts" do
      actions = Ash.Resource.Info.actions(PdfOptionsResource)
      pdf_action = Enum.find(actions, &(&1.name == :render_pdf))

      assert {AshTypst.Resource.Run, opts} = pdf_action.run
      assert opts[:pdf_options][:pdf_standards] == [:pdf_a_2b]
    end
  end

  describe "end-to-end rendering" do
    test "renders inline template as PDF with arguments" do
      input =
        Ash.ActionInput.for_action(InlineTemplateResource, :render_greeting, %{name: "World"})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :pdf
      assert is_binary(doc.data)
      assert byte_size(doc.data) > 0
      assert doc.page_count >= 1
      assert <<"%PDF", _::binary>> = doc.data
    end

    test "renders inline template as SVG with arguments" do
      input =
        Ash.ActionInput.for_action(InlineTemplateResource, :render_svg_greeting, %{name: "SVG"})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :svg
      assert is_binary(doc.data)
      assert doc.data =~ "<svg"
    end

    test "renders inline template as HTML with arguments" do
      input =
        Ash.ActionInput.for_action(InlineTemplateResource, :render_html_greeting, %{name: "HTML"})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :html
      assert is_binary(doc.data)
    end

    test "renders template with no arguments (no read)" do
      input = Ash.ActionInput.for_action(InlineTemplateResource, :render_simple, %{})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :pdf
      assert is_binary(doc.data)
      assert <<"%PDF", _::binary>> = doc.data
    end

    test "renders PDF with pdf_options" do
      input = Ash.ActionInput.for_action(PdfOptionsResource, :render_pdf, %{})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :pdf
      assert is_binary(doc.data)
    end
  end

  describe "verifiers" do
    test "ValidateTemplateRefs catches invalid template reference" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule AshTypst.ResourceTest.BadTemplateRef do
            use Ash.Resource,
              domain: AshTypst.ResourceTest.TestDomain,
              extensions: [AshTypst.Resource]

            typst do
              template :real do
                markup "= Real"
              end

              render :bad_action do
                template :nonexistent
                format :pdf
              end
            end
          end
          """)
        end)

      assert warnings =~ "no template with that name"
    end

    test "ValidateFormatOptions catches page with non-svg format" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule AshTypst.ResourceTest.BadPageFormat do
            use Ash.Resource,
              domain: AshTypst.ResourceTest.TestDomain,
              extensions: [AshTypst.Resource]

            typst do
              template :doc do
                markup "= Test"
              end

              render :bad_page do
                template :doc
                format :pdf
                page 0
              end
            end
          end
          """)
        end)

      assert warnings =~ "`page` option is only valid"
    end

    test "ValidateFormatOptions catches pdf_options with non-pdf format" do
      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("""
          defmodule AshTypst.ResourceTest.BadPdfOptions do
            use Ash.Resource,
              domain: AshTypst.ResourceTest.TestDomain,
              extensions: [AshTypst.Resource]

            typst do
              template :doc do
                markup "= Test"
              end

              render :bad_pdf_opts do
                template :doc
                format :svg
                page 0

                pdf_options do
                  pdf_standards [:pdf_a_2b]
                end
              end
            end
          end
          """)
        end)

      assert warnings =~ "`pdf_options` is only valid"
    end
  end

  describe "file-based template" do
    setup do
      dir = Path.join(System.tmp_dir!(), "ash_typst_test_#{:erlang.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      template_path = Path.join(dir, "test.typ")
      File.write!(template_path, "#import \"data.typ\": args\n= File Template #args.title")
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "renders from file template", %{dir: dir} do
      {:ok, ctx} = AshTypst.Context.new(root: dir)
      {:ok, markup} = File.read(Path.join(dir, "test.typ"))
      :ok = AshTypst.Context.set_markup(ctx, markup)

      data = "#let args = #{AshTypst.Code.encode(%{title: "From File"})}\n"
      :ok = AshTypst.Context.set_virtual_file(ctx, "data.typ", data)

      assert {:ok, %AshTypst.CompileResult{page_count: 1}} = AshTypst.Context.compile(ctx)
      assert {:ok, pdf} = AshTypst.Context.export_pdf(ctx)
      assert <<"%PDF", _::binary>> = pdf
    end
  end
end
