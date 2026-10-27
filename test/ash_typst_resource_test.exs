defmodule AshTypst.ResourceTest do
  use ExUnit.Case, async: true

  import AshTypst.Test.DslError

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

      template :site do
        markup(~TYPST"""
        #import "data.typ": args
        #document("index.html", title: [Home])[= Hello #args.name]
        #document("about.html", title: [About])[= About]
        """)
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

      render :render_site_bundle do
        template(:site)
        format(:bundle)
        pretty(true)

        argument :name, :string, allow_nil?: false
      end
    end
  end

  defmodule ConditionalArgsResource do
    use Ash.Resource,
      domain: AshTypst.ResourceTest.TestDomain,
      extensions: [AshTypst.Resource]

    typst do
      template :receipt do
        markup(~TYPST"""
        #import "data.typ": args
        Page 1 — seller: #args.seller_name
        #if args.tax_permit != "" [
          #pagebreak()
          Page with tax permit: #args.tax_permit
        ]
        #if args.center_address != "" [
          #pagebreak()
          Page with address: #args.center_address
        ]
        """)
      end

      render :render_receipt do
        template(:receipt)
        format(:pdf)

        argument :seller_name, :string, allow_nil?: false

        argument :tax_permit, :string,
          default: "",
          constraints: [allow_empty?: true]

        argument :center_address, :string,
          default: "",
          constraints: [allow_empty?: true]
      end

      render :render_receipt_string_default do
        template(:receipt)
        format(:pdf)

        argument :seller_name, :string, allow_nil?: false
        argument :tax_permit, :string, default: ""
        argument :center_address, :string, default: ""
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

  describe "DSL compilation" do
    test "resource with inline template and render action compiles" do
      assert InlineTemplateResource.__info__(:module) == InlineTemplateResource
    end

    test "resource with pdf_options compiles" do
      assert PdfOptionsResource.__info__(:module) == PdfOptionsResource
    end

    test "templates are accessible via Info" do
      templates = AshTypst.Resource.Info.templates(InlineTemplateResource)
      assert length(templates) == 3

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

    test "root accepts {otp_app, sub_path} tuple for release-friendly resolution" do
      defmodule TupleRootResource do
        use Ash.Resource,
          domain: AshTypst.ResourceTest.TestDomain,
          extensions: [AshTypst.Resource]

        typst do
          root({:ash_typst, "priv/typst"})

          template :greeting do
            markup("= hi")
          end
        end
      end

      assert {:ok, {:ash_typst, "priv/typst"}} =
               AshTypst.Resource.Info.typst_root(TupleRootResource)
    end

    test "font_paths accepts mixed list of strings and tuples" do
      defmodule MixedFontPathsResource do
        use Ash.Resource,
          domain: AshTypst.ResourceTest.TestDomain,
          extensions: [AshTypst.Resource]

        typst do
          font_paths(["priv/fonts", {:ash_typst, "priv/fonts"}])

          template :greeting do
            markup("= hi")
          end
        end
      end

      assert {:ok, ["priv/fonts", {:ash_typst, "priv/fonts"}]} =
               AshTypst.Resource.Info.typst_font_paths(MixedFontPathsResource)
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

    test "renders inline template as a bundle with arguments" do
      input =
        Ash.ActionInput.for_action(InlineTemplateResource, :render_site_bundle, %{name: "World"})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :bundle
      assert is_map(doc.data)
      assert Enum.sort(Map.keys(doc.data)) == ["about.html", "index.html"]
      assert doc.data["index.html"] =~ "Hello World"
    end

    test "renders template with no arguments (no read)" do
      input = Ash.ActionInput.for_action(InlineTemplateResource, :render_simple, %{})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :pdf
      assert is_binary(doc.data)
      assert <<"%PDF", _::binary>> = doc.data
    end

    test "empty-string argument hides conditional block via render action" do
      input =
        Ash.ActionInput.for_action(ConditionalArgsResource, :render_receipt, %{
          seller_name: "Acme",
          tax_permit: "",
          center_address: ""
        })

      assert {:ok, %AshTypst.Document{page_count: 1}} = Ash.run_action(input)
    end

    test "non-empty-string argument shows conditional block via render action" do
      input =
        Ash.ActionInput.for_action(ConditionalArgsResource, :render_receipt, %{
          seller_name: "Acme",
          tax_permit: "TP-123",
          center_address: "1 Main St"
        })

      assert {:ok, %AshTypst.Document{page_count: 3}} = Ash.run_action(input)
    end

    test "argument defaults behave identically to explicit empty strings" do
      input =
        Ash.ActionInput.for_action(ConditionalArgsResource, :render_receipt, %{
          seller_name: "Acme"
        })

      assert {:ok, %AshTypst.Document{page_count: 1}} = Ash.run_action(input)
    end

    test "mixed empty and non-empty arguments render correctly" do
      input =
        Ash.ActionInput.for_action(ConditionalArgsResource, :render_receipt, %{
          seller_name: "Acme",
          tax_permit: "",
          center_address: "1 Main St"
        })

      assert {:ok, %AshTypst.Document{page_count: 2}} = Ash.run_action(input)
    end

    test "plain :string argument without allow_empty? casts \"\" to nil, which encodes to typst `none`" do
      input =
        Ash.ActionInput.for_action(ConditionalArgsResource, :render_receipt_string_default, %{
          seller_name: "Acme",
          tax_permit: "",
          center_address: ""
        })

      assert input.arguments == %{
               seller_name: "Acme",
               tax_permit: nil,
               center_address: nil
             }

      assert {:ok, %AshTypst.Document{page_count: 3}} = Ash.run_action(input)
    end

    test "renders PDF with pdf_options" do
      input = Ash.ActionInput.for_action(PdfOptionsResource, :render_pdf, %{})

      assert {:ok, %AshTypst.Document{} = doc} = Ash.run_action(input)

      assert doc.format == :pdf
      assert is_binary(doc.data)
    end
  end

  describe "validation transformers" do
    setup do
      # Source annotations are only captured when `debug_info` is enabled, which
      # is off by default in `.exs` files. Enabling it lets the DSL errors render
      # the offending source location. See Spark's "Using Source Annotations".
      debug_info? = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, true)
      on_exit(fn -> Code.put_compiler_option(:debug_info, debug_info?) end)
      :ok
    end

    test "ValidateTemplateRefs catches invalid template reference" do
      expected = """
      [AshTypst.ResourceTest.BadTemplateRef]
      typst -> bad_action -> template defined in <FILE:LINE>:
        Render :bad_action references template :nonexistent but no template with that name is declared in the `typst` section. Declared templates: [:real]
      │
      <LINE> │               template :nonexistent
      │               ~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadTemplateRef do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          typst do
            template :real do
              markup("= Real")
            end

            render :bad_action do
              template :nonexistent
              format(:pdf)
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches page with non-svg format" do
      expected = """
      [AshTypst.ResourceTest.BadPageFormat]
      typst -> bad_page -> page defined in <FILE:LINE>:
        Render :bad_page: `page` option is only valid when `format` is `:svg`, but format is :pdf.
      │
      <LINE> │               page 0
      │               ~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadPageFormat do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          typst do
            template :doc do
              markup("= Test")
            end

            render :bad_page do
              template(:doc)
              format(:pdf)
              page 0
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches pdf_options with non-pdf format" do
      expected = """
      [AshTypst.ResourceTest.BadPdfOptions]
      typst -> bad_pdf_opts -> pdf_options defined in <FILE:LINE>:
        Render :bad_pdf_opts: `pdf_options` is only valid when `format` is `:pdf`, but format is :svg.
      │
      <LINE> │               pdf_options do
      │               ~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadPdfOptions do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          typst do
            template :doc do
              markup("= Test")
            end

            render :bad_pdf_opts do
              template(:doc)
              format(:svg)
              page(0)

              pdf_options do
                pdf_standards([:pdf_a_2b])
              end
            end
          end
        end
      end
    end

    test "ValidateCodeDerivation catches a read without deriving AshTypst.Code" do
      expected = """
      [AshTypst.ResourceTest.MissingCodeDerive]
      typst -> render_doc -> read defined in <FILE:LINE>:
        Render :render_doc declares a `read`, so the fetched records are encoded via the `AshTypst.Code` protocol, but AshTypst.ResourceTest.MissingCodeDerive does not implement it.

      Add `@derive AshTypst.Code` to the resource to use the built-in implementation (which serializes the resource's public fields), or implement the protocol directly with `defimpl AshTypst.Code, for: AshTypst.ResourceTest.MissingCodeDerive`.
      │
      <LINE> │               read :one do
      │               ~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule MissingCodeDerive do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          typst do
            template :doc do
              markup("= Test")
            end

            render :render_doc do
              template(:doc)
              format(:pdf)

              read :one do
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an undeclared argument in `filter`" do
      expected = """
      [AshTypst.ResourceTest.BadFilterArg]
      typst -> render_doc -> read -> filter defined in <FILE:LINE>:
        Render :render_doc: `filter` references argument :locaton, but the render action declares no argument with that name. Declared arguments: [:location]
      │
      <LINE> │                 filter expr(name == ^arg(:location) and kind == ^arg(:locaton))
      │                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadFilterArg do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                filter expr(name == ^arg(:location) and kind == ^arg(:locaton))
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an undeclared argument in `load`" do
      expected = """
      [AshTypst.ResourceTest.BadLoadArg]
      typst -> render_doc -> read -> load defined in <FILE:LINE>:
        Render :render_doc: `load` references argument :prefix, but the render action declares no argument with that name. Declared arguments: [:location]
      │
      <LINE> │                 load label: %{prefix: arg(:prefix)}
      │                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadLoadArg do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :one do
                load label: %{prefix: arg(:prefix)}
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an undeclared argument in `sort`" do
      expected = """
      [AshTypst.ResourceTest.BadSortArg]
      typst -> render_doc -> read -> sort defined in <FILE:LINE>:
        Render :render_doc: `sort` references argument :prefix, but the render action declares no argument with that name. Declared arguments: [:location]
      │
      <LINE> │                 sort label: {%{prefix: arg(:prefix)}, :desc}
      │                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadSortArg do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                sort label: {%{prefix: arg(:prefix)}, :desc}
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an undeclared argument in `arguments`" do
      expected = """
      [AshTypst.ResourceTest.BadArgumentsArg]
      typst -> render_doc -> read -> arguments defined in <FILE:LINE>:
        Render :render_doc: `arguments` references argument :where, but the render action declares no argument with that name. Declared arguments: [:location]
      │
      <LINE> │                 arguments %{location: arg(:where)}
      │                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadArgumentsArg do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                action :at_location
                arguments %{location: arg(:where)}
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an undeclared argument in `encoding_context`" do
      expected = """
      [AshTypst.ResourceTest.BadEncodingContextArg]
      typst -> render_doc -> encoding_context defined in <FILE:LINE>:
        Render :render_doc: `encoding_context` references argument :timezone, but the render action declares no argument with that name. Declared arguments: [:location]
      │
      <LINE> │               encoding_context %{timezone: arg(:timezone)}
      │               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadEncodingContextArg do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              encoding_context %{timezone: arg(:timezone)}
            end
          end
        end
      end
    end

    test "ValidateRead catches an unknown read action" do
      expected = """
      [AshTypst.ResourceTest.UnknownReadAction]
      typst -> render_doc -> read -> action defined in <FILE:LINE>:
        Render :render_doc: `read` uses action :nonexistent, but AshTypst.ResourceTest.UnknownReadAction has no action with that name.
      │
      <LINE> │                 action :nonexistent
      │                 ~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule UnknownReadAction do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                action :nonexistent
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an action that is not a read" do
      expected = """
      [AshTypst.ResourceTest.NotAReadAction]
      typst -> render_doc -> read -> action defined in <FILE:LINE>:
        Render :render_doc: `read` uses action :not_a_read, but its type is :action. Only read actions are supported.
      │
      <LINE> │                 action :not_a_read
      │                 ~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule NotAReadAction do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                action :not_a_read
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches an argument the read action does not accept" do
      expected = """
      [AshTypst.ResourceTest.BadReadArgument]
      typst -> render_doc -> read -> arguments defined in <FILE:LINE>:
        Render :render_doc: `arguments` sets :place, but read action :at_location accepts no argument with that name. Accepted arguments: [:location]
      │
      <LINE> │                 arguments %{place: arg(:location)}
      │                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule BadReadArgument do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                action :at_location
                arguments %{place: arg(:location)}
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `not_found` on a `:many` read" do
      expected = """
      [AshTypst.ResourceTest.ManyNotFound]
      typst -> render_doc -> read -> not_found defined in <FILE:LINE>:
        Render :render_doc: `read :many` does not support `not_found`.
      │
      <LINE> │                 not_found nil
      │                 ~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule ManyNotFound do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :many do
                not_found nil
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `limit` on a `:one` read" do
      expected = """
      [AshTypst.ResourceTest.OneLimit]
      typst -> render_doc -> read -> limit defined in <FILE:LINE>:
        Render :render_doc: `read :one` does not support `limit`.
      │
      <LINE> │                 limit 5
      │                 ~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule OneLimit do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :one do
                limit 5
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `batch_size` on a `:one` read" do
      expected = """
      [AshTypst.ResourceTest.OneBatchSize]
      typst -> render_doc -> read -> batch_size defined in <FILE:LINE>:
        Render :render_doc: `read :one` does not support `batch_size`.
      │
      <LINE> │                 batch_size 50
      │                 ~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule OneBatchSize do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :one do
                batch_size 50
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `preflight?` on a `:one` read" do
      expected = """
      [AshTypst.ResourceTest.OnePreflight]
      typst -> render_doc -> read -> preflight? defined in <FILE:LINE>:
        Render :render_doc: `read :one` does not support `preflight?`.
      │
      <LINE> │                 preflight? false
      │                 ~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule OnePreflight do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :one do
                preflight? false
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `preflight?` with `stream_with :none`" do
      expected = """
      [AshTypst.ResourceTest.UnstreamedPreflight]
      typst -> render_doc -> read -> preflight? defined in <FILE:LINE>:
        Render :render_doc: `stream_with :none` does not support `preflight?`.
      │
      <LINE> │                 preflight? false
      │                 ~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule UnstreamedPreflight do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :many do
                stream_with :none
                preflight? false
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `stream_with` on a `:one` read" do
      expected = """
      [AshTypst.ResourceTest.OneStreamWith]
      typst -> render_doc -> read -> stream_with defined in <FILE:LINE>:
        Render :render_doc: `read :one` does not support `stream_with`.
      │
      <LINE> │                 stream_with :keyset
      │                 ~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule OneStreamWith do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :at_location do
              argument :location, :string
            end

            action :not_a_read, :string do
              run fn _input, _context -> {:ok, "nope"} end
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              argument :location, :string

              read :one do
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead requires `stream_with` on a `:many` read and lists what the action supports" do
      assert_dsl_error ~r/`read :many` requires `stream_with`. Read action :read supports `stream_with :keyset`, `stream_with :offset`, `stream_with :none`./ do
        defmodule StreamWithMissing do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :many do
              end
            end
          end
        end
      end
    end

    test "ValidateRead requires `stream_with` and offers only `:none` for an unpaginated action" do
      expected = """
      [AshTypst.ResourceTest.UnpaginatedMany]
      typst -> render_doc -> read defined in <FILE:LINE>:
        Render :render_doc: `read :many` requires `stream_with`. Read action :unpaginated supports `stream_with :none`. `:keyset` and `:offset` stream the records page by page; `:none` reads every record at once.
      │
      <LINE> │               read :many do
      │               ~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule UnpaginatedMany do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]
            read :unpaginated
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :many do
                action :unpaginated
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches a `stream_with` the action's pagination does not support" do
      expected = """
      [AshTypst.ResourceTest.UnsupportedStreamWith]
      typst -> render_doc -> read -> stream_with defined in <FILE:LINE>:
        Render :render_doc: `stream_with :keyset` needs keyset pagination, but read action :by_offset does not support it. Add `keyset?: true` to the action's `pagination`, or set `stream_with :none` to read every record at once.
      │
      <LINE> │                 stream_with :keyset
      │                 ~~~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule UnsupportedStreamWith do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :by_offset do
              pagination offset?: true, required?: false
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :many do
                action :by_offset
                stream_with :keyset
              end
            end
          end
        end
      end
    end

    test "ValidateRead catches `stream_with :none` on an action that requires pagination" do
      expected = """
      [AshTypst.ResourceTest.NoneWithRequiredPagination]
      typst -> render_doc -> read -> stream_with defined in <FILE:LINE>:
        Render :render_doc: `stream_with :none` reads every record in one unpaginated read, but read action :paged requires pagination. Stream the records with `stream_with :keyset` instead.
      │
      <LINE> │                 stream_with :none
      │                 ~~~~~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule NoneWithRequiredPagination do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]

            read :paged do
              pagination keyset?: true, required?: true
            end
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :many do
                action :paged
                stream_with :none
              end
            end
          end
        end
      end
    end

    test "ValidateFormatOptions catches `batch_size` with `stream_with :none`" do
      expected = """
      [AshTypst.ResourceTest.NoneBatchSize]
      typst -> render_doc -> read -> batch_size defined in <FILE:LINE>:
        Render :render_doc: `stream_with :none` does not support `batch_size`.
      │
      <LINE> │                 batch_size 50
      │                 ~~~~~~~~~~~~~
      │
      └─ <FILE:LINE>: (file)\
      """

      assert_dsl_error expected do
        defmodule NoneBatchSize do
          use Ash.Resource,
            domain: AshTypst.ResourceTest.TestDomain,
            extensions: [AshTypst.Resource]

          @derive AshTypst.Code

          actions do
            defaults [:read]
          end

          typst do
            template :doc do
              markup "= Test"
            end

            render :render_doc do
              template :doc
              format :pdf

              read :many do
                stream_with :none
                batch_size 50
              end
            end
          end
        end
      end
    end

    test "a `:one` read does not need pagination" do
      defmodule UnpaginatedOne do
        use Ash.Resource,
          domain: AshTypst.ResourceTest.TestDomain,
          extensions: [AshTypst.Resource]

        @derive AshTypst.Code

        actions do
          defaults [:read]
          read :unpaginated
        end

        typst do
          template :doc do
            markup "= Test"
          end

          render :render_doc do
            template :doc
            format :pdf

            read :one do
              action :unpaginated
            end
          end
        end
      end

      assert UnpaginatedOne.__info__(:module) == UnpaginatedOne
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

      data = "#let args = #{AshTypst.Code.encode(%{title: "From File"}, %{})}\n"
      :ok = AshTypst.Context.set_virtual_file(ctx, "data.typ", data)

      assert {:ok, %AshTypst.CompileResult{page_count: 1}} = AshTypst.Context.compile(ctx)
      assert {:ok, pdf} = AshTypst.Context.export_pdf(ctx)
      assert <<"%PDF", _::binary>> = pdf
    end
  end
end
