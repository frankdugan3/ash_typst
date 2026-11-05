defmodule AshTypst.Resource.Template do
  @moduledoc """
  Struct and schema for the `template` entity in the `typst` DSL section.

  A template defines the Typst source to compile, either as an inline `markup`
  string or as a `source` file path relative to the configured `root` directory.
  Templates can also declare static `sys.inputs` key/value pairs.

  The `~TYPST` sigil is auto-imported inside `template` blocks, so you can use
  it directly for inline markup without any manual imports.

  Both forms are checked for Typst syntax errors at compile time: inline
  markup by the `~TYPST` sigil (see `AshTypst.Sigil`), and `source` files
  when the resource compiles, with errors reporting the template file's path,
  line and column.

  For the full DSL reference, see `d:AshTypst.Resource.typst.template`.
  """
  defstruct [:name, :source, :markup, :inputs, __identifier__: nil, __spark_metadata__: nil]

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "Unique template identifier."
    ],
    source: [
      type: :string,
      doc: """
      File path relative to the `root` directory. The file's Typst syntax is
      checked when the resource compiles (imports and other render-time
      dependencies are not resolved), and editing the file recompiles the
      resource.
      """
    ],
    markup: [
      type: :string,
      doc: "Inline Typst markup string (`~TYPST` sigil is auto-imported)."
    ],
    inputs: [
      type: :map,
      doc: "Static `sys.inputs` key/value pairs (string keys and values)."
    ]
  ]

  @doc false

  def schema, do: @schema
end
