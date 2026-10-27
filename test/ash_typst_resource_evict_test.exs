defmodule AshTypst.ResourceEvictTest do
  use ExUnit.Case, async: true

  alias AshTypst.Test.Read.Item

  setup do
    for serial_no <- ["A-1", "A-2", "A-3"] do
      Ash.create!(Item, %{serial_no: serial_no, shipped_at: ~U[2026-01-01 12:00:00Z]})
    end

    :ok
  end

  defp render(action, arguments \\ %{}) do
    Item
    |> Ash.ActionInput.for_action(action, arguments)
    |> Ash.run_action()
  end

  # Returns the result of `fun` (or what it raised) and the `max_age` of every
  # cache eviction made by the calling process meanwhile.
  defp evictions(fun) do
    test_pid = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:ash_typst, :cache, :evict],
      &__MODULE__.handle_evict/4,
      {test_pid, handler}
    )

    result =
      try do
        fun.()
      rescue
        error -> {:raised, error}
      after
        :telemetry.detach(handler)
      end

    {result, drain(handler, [])}
  end

  @doc false
  def handle_evict(_event, _measurements, %{max_age: max_age}, {test_pid, handler}) do
    if self() == test_pid, do: send(test_pid, {handler, max_age})
  end

  defp drain(handler, max_ages) do
    receive do
      {^handler, max_age} -> drain(handler, [max_age | max_ages])
    after
      0 -> Enum.reverse(max_ages)
    end
  end

  describe "AshTypst.evict_cache/1" do
    test "evicts everything by default" do
      assert {:ok, [0]} = evictions(fn -> AshTypst.evict_cache() end)
    end

    test "evicts entries older than the given age" do
      assert {:ok, [10]} = evictions(fn -> AshTypst.evict_cache(10) end)
    end
  end

  describe "a streamed render evicts the whole cache" do
    test "after it succeeds" do
      assert {{:ok, %AshTypst.Document{}}, [0]} = evictions(fn -> render(:all) end)
    end

    test "when the preflight fails" do
      assert {{:error, _error}, [0]} = evictions(fn -> render(:broken) end)
    end

    test "when the stream fails" do
      assert {{:error, _error}, [0]} = evictions(fn -> render(:failing_stream) end)
    end

    test "when encoding the stream raises" do
      assert {{:raised, _error}, [0]} = evictions(fn -> render(:raising_stream) end)
    end

    test "when the compile fails" do
      assert {{:error, _error}, [0]} = evictions(fn -> render(:broken_without_preflight) end)
    end

    test "when the export fails" do
      assert {{:error, _error}, [0]} = evictions(fn -> render(:export_failing) end)
    end
  end

  describe "a render that does not stream keeps the cache" do
    test "with `stream_with :none`" do
      assert {{:ok, %AshTypst.Document{}}, []} = evictions(fn -> render(:unstreamed) end)
    end

    test "with a `:one` read" do
      assert {{:ok, %AshTypst.Document{}}, []} = evictions(fn -> render(:one_html) end)
    end

    test "without a read" do
      assert {{:ok, %AshTypst.Document{}}, []} = evictions(fn -> render(:no_read) end)
    end
  end
end
