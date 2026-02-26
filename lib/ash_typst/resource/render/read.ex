defmodule AshTypst.Resource.Render.Read do
  @moduledoc """
  Struct and schema for the `read` sub-entity of a render action.

  The read entity controls how resource data is fetched and passed to the template.
  Use `:one` cardinality to fetch a single record (available as `record` in the
  template's data file) or `:many` to fetch a list (available as `records`, streamed
  in batches for memory efficiency).

  For the full DSL reference, see `d:AshTypst.Resource.typst.render.read`.
  """
  defstruct [
    :cardinality,
    :filter,
    :select,
    :sort,
    :limit,
    :not_found,
    load: [],
    batch_size: 100,
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          cardinality: :one | :many,
          filter: term(),
          load: [atom() | keyword()],
          select: [atom()] | nil,
          sort: term(),
          limit: non_neg_integer() | nil,
          batch_size: pos_integer(),
          not_found: :error | nil | nil,
          __spark_metadata__: Spark.Dsl.Entity.spark_meta()
        }

  @schema [
    cardinality: [
      type: {:one_of, [:one, :many]},
      required: true,
      doc: "`:one` uses `Ash.read_one`, `:many` uses `Ash.read`."
    ],
    filter: [
      type: :any,
      doc: "Ash filter expression; supports `^arg(:name)` to reference action arguments."
    ],
    load: [
      type: {:list, :any},
      default: [],
      doc: "Relationships, calculations, and aggregates to load."
    ],
    select: [
      type: {:list, :atom},
      doc: "Attributes to select (nil = all)."
    ],
    sort: [
      type: :any,
      doc: "Sort specification."
    ],
    limit: [
      type: :pos_integer,
      doc: "Max records to return (`:many` only)."
    ],
    batch_size: [
      type: :pos_integer,
      default: 100,
      doc: "Batch size for streaming large datasets into virtual file (`:many` only)."
    ],
    not_found: [
      type: {:one_of, [:error, nil]},
      default: :error,
      doc: "Behavior when `:one` finds no record."
    ]
  ]

  @doc false
  @spec schema() :: keyword()
  def schema, do: @schema
end
