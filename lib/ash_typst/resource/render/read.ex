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

  ## Choosing how a `:many` read fetches its records

  How the records are fetched decides how many of them are in memory at once,
  so a `read :many` must say so with `stream_with`. There is no default, and
  the choice is checked against the read action at compile time:

  | `stream_with` | Fetches | The read action must |
  | --- | --- | --- |
  | `:keyset` | one page of `batch_size` at a time, with `Ash.stream!/2` | support keyset pagination |
  | `:offset` | one page of `batch_size` at a time, with `Ash.stream!/2` | support offset pagination |
  | `:none` | every record in one unpaginated read | not require pagination |

      read :many do
        sort inserted_at: :asc
        stream_with :keyset
        batch_size 500
      end

  With `:keyset` or `:offset`, each page is encoded and appended to the data
  file before the next one is fetched, so only one page of records is in
  memory at a time. The default `:read` action created by `defaults [:read]`
  supports both. For a custom read action, add for example:

      read :for_report do
        pagination keyset?: true, required?: false
      end

  Prefer `:keyset`: offset pages can shift if records are inserted or deleted
  while the document is rendered. Ash appends a stable sort (the primary key,
  or the action's `stable_sort`) to every page, so either way each record is
  returned exactly once in a consistent order.

  `:none` reads and encodes every record in one go, so all of them are in
  memory while the document is rendered. Use it for small result sets, or
  for an action without pagination. `batch_size` and `preflight?` do not
  apply and are rejected.

  Whatever the pagination settings of the read action (`required?`,
  `default_limit`), all matching records are returned, subject to `limit`.

  ## Memory after a streamed render

  Typst needs far more memory than the size of its data file: in our
  measurements, about 14 times the file for parsing (freed after the
  compile), 7 times for the evaluated records, and close to 100 times for
  the laid-out pages, most of which Typst keeps in a memoization cache that
  is shared by every render in the VM.

  A streamed render re-reads its records every time, so nothing it caches
  can be reused. Once it is done, whether it succeeded, failed or raised,
  the render therefore evicts the whole cache and returns the freed memory
  to the operating system (`AshTypst.evict_cache/1`). The trade-off: the
  next render of any template in the VM starts with a cold cache, so
  template evaluation, text shaping plans and decoded images are computed
  again. Fonts, template files and assets are not part of the cache and stay
  loaded. Renders with `stream_with :none`, a `:one` read or no read keep
  the cache as before.

  Eviction lowers what stays resident after the render, not its peak. If a
  render's peak can exceed the memory the VM can spare, set `isolate? true`
  on the render: Typst then runs in a separate OS process (see
  `AshTypst.Isolated`), and the records are streamed from a task, so the
  memory used to fetch and encode them is freed when the task exits. The
  read then runs in another process than the caller: data layers that scope
  data to the calling process (a `private? true` ETS table) find nothing,
  and it can't run inside the render's transaction, so `isolate? true`,
  `transaction? true` and a streamed read are rejected together at compile
  time.

  The [Large documents](large-documents.md) guide covers these options,
  their trade-offs and capacity planning in detail.

  ## Preflight

  Typst can only compile the template once the data file is complete, so a
  mistake in the template (for example a misspelled field, or an argument the
  caller did not give) would otherwise surface only after every record has
  been fetched and encoded. For a large document, that is minutes of work
  thrown away.

  A streamed `:many` read therefore first compiles the template against the
  first page of records (`batch_size` of them, read with the same query), and
  only streams the full data when that compile succeeds. A template error is
  returned before the stream starts. The cost is one extra page read and one
  compile of that page.

  The first page is used rather than an empty list, so a template that needs
  at least one record (`records.first()`) still passes. A template that only
  fails on a record further in can still fail after the stream.

  Set `preflight? false` to skip it, for example when the first page is
  expensive to read twice.

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
    preflight?: true,
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
        "How the records are fetched. Required for `:many`, not allowed for `:one`. `:keyset` and `:offset` stream them page by page with `Ash.stream!/2`, and the read action must support that pagination type. `:none` reads them in one unpaginated read, encoded in one go, so every record is in memory at once; the read action must not require pagination, and `batch_size` is not supported. There is no default, so the choice is always visible in the DSL. All checked at compile time."
    ],
    preflight?: [
      type: :boolean,
      default: true,
      doc:
        "Compile the template against the first page of records before streaming the rest, so a template error is returned before the full data is fetched (`:many` only, not with `stream_with :none`). Costs one extra page read and one compile of that page."
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
