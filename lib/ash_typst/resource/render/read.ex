defmodule AshTypst.Resource.Render.Read do
  @moduledoc """
  Struct and schema for the `read` sub-entity of a render action.

  The read entity controls how resource data is fetched and passed to the template.
  Use `:one` cardinality to fetch a single record (available as `record` in the
  template's data file) or `:many` to fetch a list (available as `records`).

  ## Templates

  `filter`, `load`, `sort` and `arguments` are resolved at run time with Ash's
  own template resolver, so they accept the same references as an Ash read
  action: `arg/1`, `actor/1`, `tenant/0` and `context/1`. Inside `expr/1`, pin
  them (`^arg(:name)`); outside `expr/1`, call them directly:

      read :many do
        filter expr(status == ^arg(:status) and owner_id == ^actor(:id))
        load label: %{prefix: arg(:prefix)}
      end

  `select`, `limit`, `batch_size` and `stream_with` are static.

  ## Streaming `:many` reads

  A `:many` read is run with `Ash.stream!/2`: the records are fetched one page
  of `batch_size` at a time, and each page is encoded and appended to the data
  file before the next one is fetched, so only one page of records is in
  memory at a time.

  Streaming pages through the read action, so the action must support
  pagination; a `read :many` whose action has none is a compile error. The
  default `:read` action created by `defaults [:read]` supports both kinds.
  For a custom read action, add for example:

      read :for_report do
        pagination keyset?: true, required?: false
      end

  To read every record at once instead, opt out explicitly with
  `stream_with :none`: one unpaginated read, encoded in one go, so all of the
  records are in memory while the document is rendered. `batch_size` does not
  apply and is rejected.

  Keyset pagination is used when the action supports it, offset pagination
  otherwise; set `stream_with` to choose. Prefer keyset: offset pages can
  shift if records are inserted or deleted while the document is rendered.
  Ash appends a stable sort (the primary key, or the action's `stable_sort`)
  to every page, so either way each record is returned exactly once in a
  consistent order.

  Whatever the pagination settings of the read action (`required?`,
  `default_limit`), all matching records are returned, subject to `limit`.

  For the full DSL reference, see `d:AshTypst.Resource.typst.render.read`.
  """
  defstruct [
    :cardinality,
    :action,
    :filter,
    :select,
    :sort,
    :limit,
    :stream_with,
    :not_found,
    arguments: %{},
    load: [],
    batch_size: 100,
    __spark_metadata__: nil
  ]

  @schema [
    cardinality: [
      type: {:one_of, [:one, :many]},
      required: true,
      doc: "`:one` uses `Ash.read_one`, `:many` uses `Ash.stream!`."
    ],
    action: [
      type: :atom,
      doc: "The read action to run. Defaults to the primary read action."
    ],
    arguments: [
      type: {:or, [:map, :keyword_list]},
      default: %{},
      doc:
        "Arguments for the read action, e.g. `%{location_id: arg(:location_id)}`. Values support `arg/1`, `actor/1`, `tenant/0` and `context/1`."
    ],
    filter: [
      type: :any,
      doc:
        "Ash filter expression; supports `^arg(:name)`, `^actor(:field)`, `^tenant()` and `^context(:key)`."
    ],
    load: [
      type: {:list, :any},
      default: [],
      doc:
        "Relationships, calculations, and aggregates to load. Calculation arguments support `arg/1`, `actor/1`, `tenant/0` and `context/1`."
    ],
    select: [
      type: {:list, :atom},
      doc: "Attributes to select (nil = all). Does not support templates."
    ],
    sort: [
      type: :any,
      doc:
        "Sort specification. Calculation arguments support `arg/1`, `actor/1`, `tenant/0` and `context/1`."
    ],
    limit: [
      type: :pos_integer,
      doc: "Max records to return (`:many` only). Does not support templates."
    ],
    batch_size: [
      type: :pos_integer,
      default: 100,
      doc:
        "How many records are fetched and encoded into the virtual file at a time (`:many` only, not with `stream_with :none`). Capped at the `max_page_size` of the read action."
    ],
    stream_with: [
      type: {:one_of, [:keyset, :offset, :none]},
      doc:
        "How the records are fetched (`:many` only). `:keyset` and `:offset` stream them page by page with `Ash.stream!/2`, and the read action must support that pagination type. `:none` opts out of streaming: one unpaginated read, encoded in one go, so every record is in memory at once; the read action must not require pagination, and `batch_size` is not supported. Defaults to `:keyset` if the read action supports keyset pagination, and `:offset` otherwise; it never defaults to `:none`. All checked at compile time."
    ],
    not_found: [
      type: {:one_of, [:error, nil]},
      default: :error,
      doc:
        "Behavior when `:one` finds no record: `:error` returns an `Ash.Error.Query.NotFound`, `nil` renders with `record` set to `none`."
    ]
  ]

  @doc false

  def schema, do: @schema
end
