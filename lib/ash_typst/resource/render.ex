defmodule AshTypst.Resource.Render do
  @moduledoc """
  Struct and schema for the `render` entity in the `typst` DSL section.

  A render entity declares an action that compiles a template and exports it in
  the specified format (`:pdf`, `:svg`, `:html`, or `:bundle`). It can include
  arguments, a `read` sub-entity to fetch resource data, `pdf_options` for
  PDF-specific settings, and preparations/validations.

  For the full DSL reference, see `d:AshTypst.Resource.typst.render`.
  """
  defstruct [
    :name,
    :template,
    :format,
    :description,
    :page,
    pretty: false,
    render_bleed: false,
    data_file: "data.typ",
    encoding_context: %{},
    transaction?: false,
    isolate?: false,
    arguments: [],
    read: [],
    pdf_options: [],
    preparations: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "Action name (becomes the generic action name)."
    ],
    template: [
      type: :atom,
      required: true,
      doc: "Reference to a template declared in the `typst` section."
    ],
    format: [
      type: {:one_of, [:pdf, :svg, :html, :bundle]},
      required: true,
      doc: "Output export format."
    ],
    description: [
      type: :string,
      doc: "Action description."
    ],
    page: [
      type: :non_neg_integer,
      doc: "Page index for SVG rendering."
    ],
    pretty: [
      type: :boolean,
      default: false,
      doc: "Format HTML/SVG output (also within bundles) in a human-readable way."
    ],
    render_bleed: [
      type: :boolean,
      default: false,
      doc: "Include bleed margins for SVG output (also within bundles)."
    ],
    data_file: [
      type: :string,
      default: "data.typ",
      doc: "Virtual file path for serialized data."
    ],
    encoding_context: [
      type: :map,
      default: %{},
      doc:
        "Context passed to `AshTypst.Code.encode/2` for the arguments and the read results, e.g. `%{timezone: arg(:timezone)}`. Values support `arg/1`, `actor/1`, `tenant/0` and `context/1`; entries that resolve to `nil` are dropped."
    ],
    transaction?: [
      type: :boolean,
      default: false,
      doc: "Wrap action execution in a transaction."
    ],
    isolate?: [
      type: :boolean,
      default: false,
      doc:
        "Compile and export in a separate OS process that exits after the render, so its memory is returned to the OS in full, and running out of memory fails the render instead of the VM. Records are still read and encoded in the calling process. Costs starting a peer node and scanning fonts for every render. See `AshTypst.Isolated`."
    ]
  ]

  @doc false

  def schema, do: @schema

  @doc false

  def transform(render) do
    {:ok, render}
  end
end
