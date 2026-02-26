defmodule AshTypst.PDFOptions do
  @moduledoc "Options for PDF export."
  defstruct pages: nil, pdf_standards: [], document_id: nil

  @type t :: %__MODULE__{
          pages: String.t() | nil,
          pdf_standards: [:pdf_1_7 | :pdf_a_2b | :pdf_a_3b],
          document_id: String.t() | nil
        }
end
