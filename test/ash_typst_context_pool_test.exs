defmodule AshTypst.ContextPoolTest do
  use ExUnit.Case, async: true

  alias AshTypst.Context
  alias AshTypst.ContextPool

  # Distinct options per test so pools don't interfere across async tests.
  defp unique_opts do
    dir = Path.join(System.tmp_dir!(), "ash_typst_pool_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %Context.Options{root: dir}
  end

  test "checkin then checkout returns the same context" do
    opts = unique_opts()
    {:ok, ctx, generation} = ContextPool.checkout(opts)
    :ok = ContextPool.checkin(opts, ctx, generation)

    assert {:ok, ^ctx, _} = ContextPool.checkout(opts)
  end

  test "checkout creates a fresh context when the pool is empty" do
    opts = unique_opts()
    {:ok, ctx1, _} = ContextPool.checkout(opts)
    {:ok, ctx2, _} = ContextPool.checkout(opts)

    assert ctx1 != ctx2
  end

  test "contexts with different options do not share pools" do
    opts_a = unique_opts()
    opts_b = unique_opts()

    {:ok, ctx, generation} = ContextPool.checkout(opts_a)
    :ok = ContextPool.checkin(opts_a, ctx, generation)

    {:ok, other, _} = ContextPool.checkout(opts_b)
    assert other != ctx
  end

  test "checkin clears virtual files and inputs" do
    opts = unique_opts()
    {:ok, ctx, generation} = ContextPool.checkout(opts)

    :ok = Context.set_virtual_file(ctx, "leak.typ", "#let secret = \"s3cret\"")
    :ok = Context.set_input(ctx, "token", "t0ken")
    :ok = ContextPool.checkin(opts, ctx, generation)

    {:ok, ^ctx, _} = ContextPool.checkout(opts)

    :ok = Context.set_markup(ctx, "#import \"leak.typ\": secret\n#secret")
    assert {:error, %AshTypst.CompileError{}} = Context.compile(ctx)

    :ok = Context.set_markup(ctx, "#sys.inputs.at(\"token\")")
    assert {:error, %AshTypst.CompileError{}} = Context.compile(ctx)
  end

  test "flush drops idle contexts" do
    opts = unique_opts()
    {:ok, ctx, generation} = ContextPool.checkout(opts)
    :ok = ContextPool.checkin(opts, ctx, generation)

    :ok = ContextPool.flush()

    {:ok, fresh, _} = ContextPool.checkout(opts)
    assert fresh != ctx
  end

  test "contexts checked out before a flush are dropped on checkin" do
    opts = unique_opts()
    {:ok, ctx, generation} = ContextPool.checkout(opts)

    :ok = ContextPool.flush()
    :ok = ContextPool.checkin(opts, ctx, generation)

    {:ok, fresh, _} = ContextPool.checkout(opts)
    assert fresh != ctx
  end

  test "refresh_fonts flushes the pool and keeps rendering working" do
    opts = unique_opts()
    {:ok, ctx, generation} = ContextPool.checkout(opts)
    :ok = ContextPool.checkin(opts, ctx, generation)

    :ok = AshTypst.refresh_fonts()

    {:ok, fresh, _} = ContextPool.checkout(opts)
    assert fresh != ctx

    :ok = Context.set_markup(fresh, "= Fonts still work")
    assert {:ok, _} = Context.compile(fresh)
  end

  describe "with_context/2" do
    test "runs the function and returns its result" do
      opts = unique_opts()

      result =
        ContextPool.with_context(opts, fn ctx ->
          :ok = Context.set_markup(ctx, "= Pooled render")

          with {:ok, _} <- Context.compile(ctx) do
            Context.render_svg(ctx)
          end
        end)

      assert {:ok, svg} = result
      assert svg =~ "<svg"
    end

    test "accepts a keyword list of context options" do
      assert {:ok, _} =
               ContextPool.with_context([], fn ctx ->
                 :ok = Context.set_markup(ctx, "= Keyword opts")
                 Context.compile(ctx)
               end)
    end

    test "reuses the context across sequential calls" do
      opts = unique_opts()

      first = ContextPool.with_context(opts, fn ctx -> ctx end)
      second = ContextPool.with_context(opts, fn ctx -> ctx end)

      assert first == second
    end

    test "returns the context to the pool when the function raises" do
      opts = unique_opts()
      ctx = ContextPool.with_context(opts, fn ctx -> ctx end)

      assert_raise RuntimeError, "boom", fn ->
        ContextPool.with_context(opts, fn _ctx -> raise "boom" end)
      end

      assert {:ok, ^ctx, _} = ContextPool.checkout(opts)
    end

    test "clears state between calls" do
      opts = unique_opts()

      ContextPool.with_context(opts, fn ctx ->
        :ok = Context.set_virtual_file(ctx, "leak.typ", "#let secret = 1")
      end)

      result =
        ContextPool.with_context(opts, fn ctx ->
          :ok = Context.set_markup(ctx, "#import \"leak.typ\": secret\n#secret")
          Context.compile(ctx)
        end)

      assert {:error, %AshTypst.CompileError{}} = result
    end
  end
end
