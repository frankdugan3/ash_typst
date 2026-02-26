defmodule AshTypst.Resource.Render.PdfOptions do
  @moduledoc """
  Struct and schema for the `pdf_options` sub-entity of a render action.

  Only valid when the render action's format is `:pdf`. Allows configuring page
  ranges, PDF compliance standards, and document identifiers.

  For the full DSL reference, see `d:AshTypst.Resource.typst.render.pdf_options`.
  """
  defstruct [:pages, :document_id, pdf_standards: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          pages: String.t() | nil,
          pdf_standards: [:pdf_1_7 | :pdf_a_2b | :pdf_a_3b],
          document_id: String.t() | nil,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  @schema [
    pages: [
      type: :string,
      doc: "Page range, 1-indexed (e.g., `\"1-3,5,7-9\"`)."
    ],
    pdf_standards: [
      type: {:list, {:one_of, [:pdf_1_7, :pdf_a_2b, :pdf_a_3b]}},
      default: [],
      doc: "PDF compliance standards."
    ],
    document_id: [
      type: :string,
      doc: "PDF document identifier."
    ]
  ]

  @doc false
  @spec schema() :: keyword()
  def schema, do: @schema
end
