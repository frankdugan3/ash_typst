defmodule AshTypst.ContextPool do
  @moduledoc """
  Pool of reusable `AshTypst.Context`s.

  Contexts are pooled per configuration (`AshTypst.Context.Options`), so
  callers with identical `root`/`font_paths`/`ignore_system_fonts`
  settings share the same pool. Reuse avoids re-creating the Rust-side
  world (and its package resolver) on every render.

  `AshTypst.Resource` render actions always render through this pool. For
  direct `AshTypst.Context` usage the pool is opt-in — wrap each render in
  `with_context/2`. This shines in high-frequency workflows like a
  real-time preview editor, where every keystroke triggers a render:

      AshTypst.ContextPool.with_context([root: template_dir], fn ctx ->
        :ok = AshTypst.Context.set_markup(ctx, editor_buffer)

        with {:ok, _} <- AshTypst.Context.compile(ctx) do
          AshTypst.Context.render_svg(ctx, page: current_page)
        end
      end)

  The pool process only brokers checkouts — contexts are created in the
  caller when no idle one is available, and renders run entirely in the
  caller. At most `System.schedulers_online()` idle contexts are retained
  per configuration; surplus check-ins are dropped and freed by the GC.

  Before a context is returned to the pool, its virtual files and
  `sys.inputs` are cleared so no data leaks between renders. Markup is
  always set by the next render.
  """
  use GenServer

  alias AshTypst.Context

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Run `fun` with a pooled context and return its result.

  Checks out a context for `opts` (creating one if none is idle), calls
  `fun` with it, and returns the context to the pool afterwards — also
  when `fun` raises. Accepts the same options as `AshTypst.Context.new/1`,
  as a keyword list or an `AshTypst.Context.Options` struct.

  Do not use the context outside `fun` — after `fun` returns, the context
  may be handed to another caller at any time.
  """
  def with_context(opts \\ [], fun)

  def with_context(%Context.Options{} = opts, fun) when is_function(fun, 1) do
    {:ok, ctx, generation} = checkout(opts)

    try do
      fun.(ctx)
    after
      checkin(opts, ctx, generation)
    end
  end

  def with_context(opts, fun) when is_list(opts) do
    with_context(struct!(Context.Options, opts), fun)
  end

  @doc """
  Check out an idle context pooled for `opts`, creating one if none is idle.

  Returns `{:ok, ctx, generation}`; pass the generation back to `checkin/3`
  when done (typically in an `after` block). A context lost to a crashed
  caller is simply garbage collected — the pool replaces it on demand.

  Prefer `with_context/2`, which pairs the checkout and check-in for you.
  """
  def checkout(%Context.Options{} = opts) do
    case GenServer.call(__MODULE__, {:checkout, opts}) do
      {:ok, ctx, generation} ->
        {:ok, ctx, generation}

      {:empty, generation} ->
        with {:ok, ctx} <- Context.new(opts), do: {:ok, ctx, generation}
    end
  end

  @doc """
  Clear per-render state and return a context to the pool for `opts`.

  If `flush/0` was called since this context was checked out (its
  generation is stale), the context is dropped instead of pooled.
  """
  def checkin(%Context.Options{} = opts, ctx, generation) do
    :ok = Context.clear_virtual_files(ctx)
    :ok = Context.set_inputs(ctx, %{})
    GenServer.cast(__MODULE__, {:checkin, opts, ctx, generation})
  end

  @doc """
  Drop all idle contexts from every pool.

  Subsequent checkouts create fresh contexts, and contexts checked out
  before the flush are dropped when checked back in. Used by
  `AshTypst.refresh_fonts/0` so renders pick up a fresh font scan.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl true
  def init(opts) do
    max_idle = Keyword.get(opts, :max_idle, System.schedulers_online())
    {:ok, %{max_idle: max_idle, generation: 0, idle: %{}}}
  end

  @impl true
  def handle_call({:checkout, key}, _from, state) do
    case Map.get(state.idle, key, []) do
      [ctx | rest] ->
        {:reply, {:ok, ctx, state.generation}, %{state | idle: Map.put(state.idle, key, rest)}}

      [] ->
        {:reply, {:empty, state.generation}, state}
    end
  end

  def handle_call(:flush, _from, state) do
    {:reply, :ok, %{state | generation: state.generation + 1, idle: %{}}}
  end

  @impl true
  def handle_cast({:checkin, key, ctx, generation}, state) do
    idle = Map.get(state.idle, key, [])

    if generation == state.generation and length(idle) < state.max_idle do
      {:noreply, %{state | idle: Map.put(state.idle, key, [ctx | idle])}}
    else
      {:noreply, state}
    end
  end
end
