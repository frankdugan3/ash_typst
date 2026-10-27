defmodule AshTypst.Isolated do
  @moduledoc """
  Render in a separate OS process that exits afterwards.

  Compiling a large document takes memory far beyond the size of its data:
  the syntax tree, the evaluated values and above all the laid-out pages,
  which Typst also keeps in its memoization cache. `AshTypst.evict_cache/1`
  frees that cache, but a render in the VM still peaks inside the VM: a
  render that needs more memory than the machine has takes the whole VM
  down, and some memory stays resident afterwards.

  `with_context/2` instead starts a peer node (`:peer`, a second Erlang VM
  that loads the same code) and creates the context there. When the
  function returns, the peer exits and the operating system takes back
  every byte it used. If the peer runs out of memory and is killed, the
  calls on its context raise `AshTypst.Isolated.Error`, and the calling
  VM is unaffected.

      AshTypst.Isolated.with_context([root: template_dir], fn ctx ->
        :ok = AshTypst.Context.set_markup(ctx, markup)
        :ok = AshTypst.Context.stream_virtual_file(ctx, "data.typ", records, variable_name: "records")

        with {:ok, _} <- AshTypst.Context.compile(ctx) do
          AshTypst.Context.export_pdf(ctx)
        end
      end)

  The context works with every `AshTypst.Context` function. Data is encoded
  in the calling process and sent to the peer, so streaming keeps the
  caller's memory flat as usual. Render actions use this with
  `isolate? true`.

  ## Costs

    * Starting the peer and loading the NIF takes a fraction of a second,
      and every peer scans fonts again (the font cache is per VM).
    * Nothing is cached between renders, neither contexts nor memoized
      results.
    * Small values travel over the peer's standard I/O. Binaries larger
      than 64 KB (data chunks, the exported document) are passed through
      files in a private directory (mode `0700`) under
      `System.tmp_dir!/0`, which is removed afterwards. Rendered data
      touches the disk there.

  The peer is started with the `erl` of the running Erlang installation
  (`:code.root_dir/0`), which is also present in a Mix release that
  includes ERTS, and with the code paths of the calling VM.

  See the [Large documents](large-documents.md) guide for when to use it.
  """

  alias AshTypst.Context
  alias AshTypst.NIF

  @enforce_keys [:peer, :spool]
  defstruct [:peer, :spool]

  @type t :: %__MODULE__{peer: pid(), spool: Path.t()}

  # The standard I/O connection of `:peer` encodes every byte as two and
  # decodes them one at a time: about 0.2 seconds per MB. Larger binaries go
  # through the spool directory instead.
  @inline_limit 64 * 1024

  @context_key {__MODULE__, :context}

  defmodule Error do
    @moduledoc """
    Raised when the peer node of an `AshTypst.Isolated` context fails to
    start or exits during a call, for example when the operating system
    kills it for running out of memory.
    """
    defexception [:reason]

    @impl true
    def message(%{reason: reason}) do
      "the isolated Typst renderer exited: #{inspect(reason)}"
    end
  end

  @doc """
  Run `fun` with a context in a new peer node, then stop the node.

  Accepts the same options as `AshTypst.Context.new/1`, as a keyword list
  or an `AshTypst.Context.Options` struct. Returns the result of `fun`.
  The peer is stopped when `fun` returns or raises, and also when the
  calling process exits.

  Do not use the context outside `fun`.
  """
  def with_context(opts \\ [], fun)

  def with_context(%Context.Options{} = opts, fun) when is_function(fun, 1) do
    spool = make_spool!()

    try do
      peer = start_peer!()

      try do
        isolated = %__MODULE__{peer: peer, spool: spool}
        :ok = remote(isolated, :remote_init, [opts])
        fun.(isolated)
      after
        stop_peer(peer)
      end
    after
      File.rm_rf(spool)
    end
  end

  def with_context(opts, fun) when is_list(opts) do
    with_context(struct!(Context.Options, opts), fun)
  end

  @doc false
  # Called by `AshTypst.Context` for every function on an isolated context.
  def call(%__MODULE__{} = isolated, fun, args) do
    remote(isolated, :remote_apply, [fun, args])
  end

  defp remote(%__MODULE__{peer: peer, spool: spool}, fun, args) do
    args = spool(args, spool)

    peer
    |> :peer.call(__MODULE__, fun, [spool | args], :infinity)
    |> unspool()
  catch
    :exit, reason -> raise Error, reason: reason
  end

  # Runs on the peer.
  @doc false
  def remote_init(_spool, opts) do
    :persistent_term.put(@context_key, NIF.context_new(opts))
    :ok
  end

  # Runs on the peer.
  @doc false
  def remote_apply(spool, fun, args) do
    ctx = :persistent_term.get(@context_key)

    NIF
    |> apply(fun, [ctx | unspool(args)])
    |> spool(spool)
  end

  defp make_spool! do
    name = "ash_typst-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    path = Path.join(System.tmp_dir!(), name)

    # `mkdir!` fails on an existing directory, so nobody can prepare one.
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    path
  end

  defp start_peer! do
    caller = self()

    options =
      %{
        connection: :standard_io,
        args: [~c"-noshell", ~c"-pa" | :code.get_path()]
      }
      |> put_exec()

    case :peer.start(options) do
      {:ok, peer, _node} ->
        watch(caller, peer)
        peer

      {:error, reason} ->
        raise Error, reason: reason
    end
  end

  # `:peer` looks for `erl` on the `PATH` by default, which a release does
  # not need to have. Prefer the `erl` of the running installation.
  defp put_exec(options) do
    erl =
      Path.join([
        to_string(:code.root_dir()),
        "erts-#{:erlang.system_info(:version)}",
        "bin",
        "erl"
      ])

    if File.exists?(erl), do: Map.put(options, :exec, String.to_charlist(erl)), else: options
  end

  # The peer is not linked to the caller, so that its death does not kill
  # the caller. This stops the peer when the caller dies first.
  defp watch(caller, peer) do
    spawn(fn ->
      caller_ref = Process.monitor(caller)
      peer_ref = Process.monitor(peer)

      receive do
        {:DOWN, ^caller_ref, :process, _pid, _reason} -> stop_peer(peer)
        {:DOWN, ^peer_ref, :process, _pid, _reason} -> :ok
      end
    end)
  end

  defp stop_peer(peer) do
    :peer.stop(peer)
  catch
    # Already stopped, for example after the node was killed.
    :exit, _reason -> :ok
  end

  # Replaces large binaries with files in the spool directory, wherever they
  # are in the term.
  defp spool(binary, spool) when is_binary(binary) and byte_size(binary) > @inline_limit do
    path = Path.join(spool, "#{System.unique_integer([:positive])}-#{System.pid()}")
    File.write!(path, binary)
    {__MODULE__, :spooled, path}
  end

  defp spool(list, spool) when is_list(list), do: Enum.map(list, &spool(&1, spool))

  defp spool(map, spool) when is_map(map) do
    :maps.map(fn _key, value -> spool(value, spool) end, map)
  end

  defp spool(tuple, spool) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> spool(spool) |> List.to_tuple()
  end

  defp spool(term, _spool), do: term

  defp unspool({__MODULE__, :spooled, path}) do
    binary = File.read!(path)
    File.rm!(path)
    binary
  end

  defp unspool(list) when is_list(list), do: Enum.map(list, &unspool/1)
  defp unspool(map) when is_map(map), do: :maps.map(fn _key, value -> unspool(value) end, map)

  defp unspool(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> unspool() |> List.to_tuple()
  end

  defp unspool(term), do: term
end
