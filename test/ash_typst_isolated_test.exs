defmodule AshTypst.IsolatedTest do
  # The isolated renders read `AshTypst.Test.Read.Shared`, whose ETS table is
  # shared by every process.
  use ExUnit.Case, async: false

  import AshTypst.Test.DslError

  alias Ash.DataLayer.Ets
  alias AshTypst.Context
  alias AshTypst.Isolated
  alias AshTypst.Test.Read.Shared

  describe "with_context/2" do
    test "runs the context in another OS process" do
      Isolated.with_context(fn ctx ->
        refute :peer.call(ctx.peer, :os, :getpid, []) == :os.getpid()
      end)
    end

    test "supports the AshTypst.Context functions" do
      result =
        Isolated.with_context(fn ctx ->
          :ok = Context.set_markup(ctx, ~S|#import "data.typ": records
#records.join(",")|)

          :ok =
            Context.stream_virtual_file(ctx, "data.typ", ["a", "b"], variable_name: "records")

          {:ok, %AshTypst.CompileResult{page_count: 1}} = Context.compile(ctx)
          {:ok, svg} = Context.render_svg(ctx)
          {:ok, html} = Context.export_html(ctx)
          {:ok, pdf} = Context.export_pdf(ctx)
          {svg, html, pdf}
        end)

      assert {"<svg" <> _, html, "%PDF" <> _} = result
      assert html =~ "a,b"
    end

    test "returns compile errors with their diagnostics" do
      assert {:error, %AshTypst.CompileError{diagnostics: [%{severity: :error} | _]}} =
               Isolated.with_context(fn ctx ->
                 :ok = Context.set_markup(ctx, "#unknown")
                 Context.compile(ctx)
               end)
    end

    test "passes large binaries both ways and removes them afterwards" do
      blob = :crypto.strong_rand_bytes(1024 * 1024)

      html =
        Isolated.with_context(fn ctx ->
          :ok = Context.set_virtual_file_binary(ctx, "blob", blob)
          # The page repeats the length often enough to exceed the inline limit.
          :ok =
            Context.set_markup(
              ctx,
              ~S|#for _ in range(20000) [#read("blob", encoding: none).len() ]|
            )

          {:ok, html} = Context.export_html(ctx)
          assert File.ls!(ctx.spool) == []
          html
        end)

      assert byte_size(html) > 64 * 1024
      assert html =~ "1048576"
    end

    test "stops the peer and removes the spool directory when the function returns" do
      ctx = Isolated.with_context(& &1)

      refute Process.alive?(ctx.peer)
      refute File.exists?(ctx.spool)
    end

    test "stops the peer when the function raises" do
      test_pid = self()

      assert_raise RuntimeError, fn ->
        Isolated.with_context(fn ctx ->
          send(test_pid, {:ctx, ctx})
          raise "boom"
        end)
      end

      assert_received {:ctx, ctx}
      refute Process.alive?(ctx.peer)
    end

    test "stops the peer when the caller exits" do
      test_pid = self()

      caller =
        spawn(fn ->
          Isolated.with_context(fn ctx ->
            send(test_pid, {:ctx, ctx})
            Process.sleep(:infinity)
          end)
        end)

      assert_receive {:ctx, ctx}, 10_000
      ref = Process.monitor(ctx.peer)
      Process.exit(caller, :kill)

      assert_receive {:DOWN, ^ref, :process, _pid, _reason}, 10_000
    end

    test "raises when the peer is killed" do
      assert_raise Isolated.Error, fn ->
        Isolated.with_context(fn ctx ->
          os_pid = :peer.call(ctx.peer, :os, :getpid, [])
          {_, 0} = System.cmd("kill", ["-9", to_string(os_pid)])
          :ok = Context.set_markup(ctx, "= Hello")
          Context.compile(ctx)
        end)
      end
    end
  end

  describe "render actions with `isolate? true`" do
    setup do
      for serial_no <- ["A-1", "A-2", "A-3"] do
        Ash.create!(Shared, %{serial_no: serial_no, shipped_at: ~U[2026-01-01 12:00:00Z]})
      end

      on_exit(fn -> Ets.stop(Shared) end)
    end

    defp render(action) do
      Shared
      |> Ash.ActionInput.for_action(action, %{})
      |> Ash.run_action()
    end

    # The test templates print their values between square brackets.
    defp printed({:ok, %AshTypst.Document{data: html}}) do
      [_, printed] = Regex.run(~r/\[([^\]]*)\]/, html)
      printed
    end

    # Returns the result of `fun` and the processes that read `Shared`.
    defp readers(fun) do
      test_pid = self()
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:ash, :domain, :read, :start],
        &__MODULE__.handle_read/4,
        {test_pid, handler}
      )

      result = fun.()
      :telemetry.detach(handler)

      {result, drain(handler, [])}
    end

    @doc false
    def handle_read(_event, _measurements, metadata, {test_pid, handler}) do
      if metadata.resource_short_name == :shared, do: send(test_pid, {handler, self()})
    end

    defp drain(handler, pids) do
      receive do
        {^handler, pid} -> drain(handler, [pid | pids])
      after
        0 -> Enum.reverse(pids)
      end
    end

    test "render the streamed records" do
      assert render(:all_isolated) |> printed() == "A-1,A-2,A-3"

      assert {:ok, %AshTypst.Document{format: :pdf, data: "%PDF" <> _}} =
               render(:all_isolated_pdf)
    end

    test "read the first page in the caller and stream the rest from another process" do
      {result, [preflight | stream]} = readers(fn -> render(:all_isolated) end)

      assert {:ok, %AshTypst.Document{}} = result
      assert preflight == self()
      assert [_ | _] = stream
      assert Enum.all?(stream, &(&1 != self()))
    end

    test "render records read with `stream_with :none` in the caller" do
      {result, readers} = readers(fn -> render(:unstreamed_isolated) end)

      assert printed(result) == "A-1,A-2,A-3"
      assert readers == [self()]
    end

    test "do not evict the cache of the calling VM" do
      test_pid = self()
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:ash_typst, :cache, :evict],
        &__MODULE__.handle_evict/4,
        {test_pid, handler}
      )

      assert {:ok, _document} = render(:all_isolated)
      :telemetry.detach(handler)

      refute_received ^handler
    end

    @doc false
    def handle_evict(_event, _measurements, _metadata, {test_pid, handler}) do
      send(test_pid, handler)
    end

    test "return template errors from the preflight and from the full compile" do
      assert {:error, _error} = render(:broken_isolated)
      assert {:error, _error} = render(:broken_isolated_without_preflight)
    end

    test "return an error when the stream fails" do
      assert {:error, _error} = render(:failing_stream_isolated)
    end

    test "raise in the caller what the stream raises" do
      # Ash wraps what an action raises, so look for the original error in it.
      error = assert_raise Ash.Error.Unknown, fn -> render(:raising_stream_isolated) end
      assert Exception.message(error) =~ "(ArgumentError) cannot shift"
    end
  end

  test "`isolate? true` can't stream a read inside a transaction" do
    assert_dsl_error ~r/`isolate\? true` streams the records of its `read :many`/ do
      defmodule IsolatedTransaction do
        use Ash.Resource,
          domain: AshTypst.Test.Read.Domain,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshTypst.Resource]

        @derive AshTypst.Code

        attributes do
          uuid_primary_key :id
        end

        actions do
          defaults [:read]
        end

        typst do
          template :doc do
            markup "= Test"
          end

          render :render_doc do
            template :doc
            format :pdf
            isolate? true
            transaction? true

            read :many do
              stream_with :keyset
            end
          end
        end
      end
    end
  end
end
