defmodule AshTypst.Resource.Render do
  @moduledoc """
  Struct and schema for the `render` entity in the `typst` DSL section.

  A render entity declares an action that compiles a template and exports it in
  the specified format (`:pdf`, `:svg`, or `:html`). It can include arguments,
  a `read` sub-entity to fetch resource data, `pdf_options` for PDF-specific
  settings, and preparations/validations.

  For the full DSL reference, see `d:AshTypst.Resource.typst.render`.
  """
  defstruct [
    :name,
    :template,
    :format,
    :description,
    :page,
    data_file: "data.typ",
    transaction?: false,
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
      type: {:one_of, [:pdf, :svg, :html]},
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
    data_file: [
      type: :string,
      default: "data.typ",
      doc: "Virtual file path for serialized data."
    ],
    transaction?: [
      type: :boolean,
      default: false,
      doc: "Wrap action execution in a transaction."
    ]
  ]

  @doc false

  def schema, do: @schema

  @doc false

  def transform(render) do
    {:ok, render}
  end
end
