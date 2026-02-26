defmodule AshTypst.Resource do
  @moduledoc """
  Spark DSL extension for rendering Typst templates as Ash generic actions.

  This extension adds a `typst` DSL section to your Ash resource where you can
  declare reusable templates and render actions. Each render action is transformed
  into an Ash generic action that compiles and exports a Typst document, returning
  an `AshTypst.Document` struct.

  ## Usage

  Add the extension to your resource:

      defmodule MyApp.Invoice do
        use Ash.Resource,
          domain: MyApp.Domain,
          extensions: [AshTypst.Resource]

        typst do
          root "priv/typst"

          template :invoice do
            source "invoice.typ"
            inputs %{"company" => "Acme Corp"}
          end

          template :receipt do
            # ~TYPST sigil is auto-imported in template blocks
            markup ~TYPST\"\"\"
            #import "data.typ": record, args
            = Receipt \#args.receipt_number
            *Customer:* \#record.name
            \"\"\"
          end

          render :generate_pdf do
            template :invoice
            format :pdf

            argument :invoice_id, :string, allow_nil?: false

            read :one do
              filter expr(id == ^arg(:invoice_id))
              load [:line_items, :customer]
            end

            pdf_options do
              pdf_standards [:pdf_a_2b]
            end
          end
        end
      end

  Then call the action like any other Ash generic action:

      input = Ash.ActionInput.for_action(MyApp.Invoice, :generate_pdf, %{invoice_id: "123"})
      {:ok, %AshTypst.Document{format: :pdf, data: pdf_binary}} = Ash.run_action(input)

  ## How It Works

  1. **Templates** are declared in the `typst` section. Each template has either an
     inline `markup` string (the `~TYPST` sigil is auto-imported inside `template`
     blocks) or a `source` file path relative to the `root` directory.

  2. **Render actions** reference a template and specify an output `format` (`:pdf`,
     `:svg`, or `:html`). They can optionally declare arguments, a `read` to fetch
     resource data, and format-specific options like `pdf_options`.

  3. At compile time, the `BuildActions` transformer converts each render entity into
     a standard `Ash.Resource.Actions.Action`.

  4. At runtime, the action implementation creates a context, sets the template,
     injects data (arguments and/or read results) into a virtual file, compiles, and
     exports in the requested format.

  ## Data Injection

  The render action injects data into a virtual file (default `"data.typ"`) that your
  template can `#import`:

  - **No read**: only `args` (a dictionary of action arguments) is available.
  - **Read `:one`**: both `record` (the single resource) and `args` are available.
  - **Read `:many`**: `records` (an array, streamed in batches) and `args` are available.

  ## DSL Reference

  For the complete DSL reference with all options, see `d:AshTypst.Resource`.
  """

  @template %Spark.Dsl.Entity{
    name: :template,
    describe: "Declares a reusable Typst template.",
    target: AshTypst.Resource.Template,
    args: [:name],
    identifier: :name,
    imports: [AshTypst.Sigil],
    schema: AshTypst.Resource.Template.schema()
  }

  @action_argument %Spark.Dsl.Entity{
    name: :argument,
    describe: "Declares an argument on the action.",
    target: Ash.Resource.Actions.Argument,
    args: [:name, :type],
    transform: {Ash.Type, :set_type_transformation, []},
    schema: Ash.Resource.Actions.Argument.schema()
  }

  @read %Spark.Dsl.Entity{
    name: :read,
    describe: "Declares how to fetch resource data to pass to the template.",
    target: AshTypst.Resource.Render.Read,
    args: [:cardinality],
    imports: [Ash.Expr],
    schema: AshTypst.Resource.Render.Read.schema()
  }

  @pdf_options %Spark.Dsl.Entity{
    name: :pdf_options,
    describe: "PDF-specific export options.",
    target: AshTypst.Resource.Render.PdfOptions,
    schema: AshTypst.Resource.Render.PdfOptions.schema()
  }

  @prepare %Spark.Dsl.Entity{
    name: :prepare,
    describe: "Declares a preparation that runs before the template is rendered.",
    target: Ash.Resource.Preparation,
    schema: Ash.Resource.Preparation.schema(),
    no_depend_modules: [:preparation],
    args: [:preparation]
  }

  @action_validate %Spark.Dsl.Entity{
    name: :validate,
    describe: "Declares a validation for this action.",
    target: Ash.Resource.Validation,
    schema: Ash.Resource.Validation.action_schema(),
    no_depend_modules: [:validation],
    transform: {Ash.Resource.Validation, :transform, []},
    args: [:validation]
  }

  @render %Spark.Dsl.Entity{
    name: :render,
    describe: "Declares a Typst template rendering action.",
    target: AshTypst.Resource.Render,
    args: [:name],
    identifier: :name,
    imports: [
      Ash.Resource.Preparation.Builtins,
      Ash.Resource.Validation.Builtins,
      Ash.Expr
    ],
    schema: AshTypst.Resource.Render.schema(),
    transform: {AshTypst.Resource.Render, :transform, []},
    singleton_entity_keys: [:read, :pdf_options],
    entities: [
      arguments: [@action_argument],
      read: [@read],
      pdf_options: [@pdf_options],
      preparations: [@prepare, @action_validate]
    ]
  }

  @typst_section %Spark.Dsl.Section{
    name: :typst,
    describe: "Configuration for Typst template rendering.",
    schema: [
      root: [
        type: :string,
        default: "priv/typst",
        doc: "Root directory for template file resolution."
      ],
      font_paths: [
        type: {:list, :string},
        default: [],
        doc: "Additional font search directories."
      ],
      ignore_system_fonts: [
        type: :boolean,
        default: false,
        doc: "Skip system font loading."
      ]
    ],
    entities: [@template, @render]
  }

  use Spark.Dsl.Extension,
    sections: [@typst_section],
    transformers: [
      AshTypst.Resource.Transformers.BuildActions
    ],
    verifiers: [
      AshTypst.Resource.Verifiers.ValidateTemplateRefs,
      AshTypst.Resource.Verifiers.ValidateFormatOptions
    ]
end
