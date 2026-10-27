defmodule AshTypst.ResourceReadTest do
  use ExUnit.Case, async: true

  alias AshTypst.Test.Read.Item
  alias AshTypst.Test.Read.Secured

  @alice "7c2f4a1e-5b0d-4a52-9d2e-0f6f1a3b9c01"
  @bob "7c2f4a1e-5b0d-4a52-9d2e-0f6f1a3b9c02"

  setup do
    for {serial_no, packing_slip_no, location, status, owner_id} <- [
          {"A-1", "PS-1", "north", :packed, @alice},
          {"A-2", "PS-1", "south", :shipped, @bob},
          {"A-3", "PS-2", "north", :packed, @alice},
          {"A-4", "PS-2", "south", :returned, @bob},
          {"A-5", "PS-3", nil, :packed, nil}
        ] do
      Ash.create!(Item, %{
        serial_no: serial_no,
        packing_slip_no: packing_slip_no,
        location: location,
        status: status,
        owner_id: owner_id,
        shipped_at: ~U[2026-01-01 12:00:00Z]
      })
    end

    :ok
  end

  defp render(action, arguments, opts \\ []) do
    Item
    |> Ash.ActionInput.for_action(action, arguments)
    |> Ash.run_action(opts)
  end

  defp render_secured(action, opts) do
    Secured
    |> Ash.ActionInput.for_action(action, %{})
    |> Ash.run_action(opts)
  end

  # The test templates print their values between square brackets.
  defp printed({:ok, %AshTypst.Document{data: html}}) do
    [_, printed] = Regex.run(~r/\[([^\]]*)\]/, html)
    printed
  end

  defp serial_nos(result) do
    result |> printed() |> String.split(",", trim: true)
  end

  # Counts the data layer reads of `Item` made by the calling process.
  defp count_reads(fun) do
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

    {result, drain(handler, 0)}
  end

  @doc false
  def handle_read(_event, _measurements, metadata, {test_pid, message}) do
    if self() == test_pid and metadata.resource_short_name == :item do
      send(test_pid, message)
    end
  end

  defp drain(message, count) do
    receive do
      ^message -> drain(message, count + 1)
    after
      0 -> count
    end
  end

  describe "filter templates" do
    test "two `^arg` conditions joined with `and`" do
      assert serial_nos(render(:by_and, %{packing_slip_no: "PS-1", location: "north"})) == ["A-1"]
    end

    test "two `^arg` conditions joined with `and` on a `:one` read" do
      assert printed(render(:one_by_and, %{packing_slip_no: "PS-2", serial_no: "A-4"})) == "A-4"
    end

    test "two `^arg` conditions joined with `or`" do
      assert serial_nos(render(:by_or, %{packing_slip_no: "PS-1", location: "north"})) ==
               ["A-1", "A-2", "A-3"]
    end

    test "an `^arg` condition wrapped in `not`" do
      assert serial_nos(render(:by_not, %{location: "north"})) == ["A-2", "A-4"]
    end

    test "`attribute in ^arg(:list)`" do
      assert serial_nos(render(:by_in, %{statuses: [:shipped, :returned]})) == ["A-2", "A-4"]
    end

    test "`^arg` inside a list" do
      assert serial_nos(render(:by_list_of_args, %{first: "A-1", second: "A-4"})) ==
               ["A-1", "A-4"]
    end

    test "`^arg` inside a nested function call" do
      assert serial_nos(render(:by_nested_call, %{serial_no: "a-3", location: "north"})) ==
               ["A-3"]
    end

    test "`arg` in a keyword filter" do
      assert serial_nos(render(:by_keyword, %{location: "south"})) == ["A-2", "A-4"]
    end

    test "`^actor`" do
      assert serial_nos(render(:by_actor, %{}, actor: %{id: @alice})) == ["A-1", "A-3"]
    end

    test "`^tenant`" do
      assert serial_nos(render(:by_tenant, %{}, tenant: "south")) == ["A-2", "A-4"]
    end

    test "`^context`" do
      assert serial_nos(render(:by_context, %{}, context: %{location: "north"})) ==
               ["A-1", "A-3"]
    end

    test "a `nil` argument compares as `nil`, so the filter matches no record" do
      assert serial_nos(render(:by_nilable, %{})) == []
      assert serial_nos(render(:by_nilable, %{location: "north"})) == ["A-1", "A-3"]
    end
  end

  describe "load and sort templates" do
    test "`arg` as a calculation argument in `load`" do
      assert serial_nos(render(:load_with_arg, %{prefix: "X/"})) ==
               ["X/A-1", "X/A-2", "X/A-3", "X/A-4", "X/A-5"]
    end

    test "`arg` as a calculation argument in `sort`" do
      assert serial_nos(render(:sort_with_arg, %{prefix: "X/"})) ==
               ["A-5", "A-4", "A-3", "A-2", "A-1"]
    end
  end

  describe "streaming a `:many` read" do
    test "a default read action supports keyset pagination, so it is read in batches" do
      assert {result, 3} = count_reads(fn -> render(:all, %{}) end)
      assert serial_nos(result) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "an action with keyset pagination is read in batches of `batch_size`" do
      assert {result, 3} = count_reads(fn -> render(:all_keyset, %{}) end)
      assert serial_nos(result) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "`stream_with` chooses the strategy" do
      assert {result, 3} = count_reads(fn -> render(:forced_offset, %{}) end)
      assert serial_nos(result) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "`stream_with :none` reads an unpaginated action once" do
      assert {result, 1} = count_reads(fn -> render(:unstreamed, %{}) end)
      assert serial_nos(result) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "`stream_with :none` encodes one record and no records as arrays" do
      assert serial_nos(render(:unstreamed_filtered, %{serial_no: "A-3"})) == ["A-3"]
      assert serial_nos(render(:unstreamed_filtered, %{serial_no: "nope"})) == []
    end

    test "`stream_with :none` reads a paginated action once, without a page" do
      assert {result, 1} = count_reads(fn -> render(:unstreamed_paginated, %{}) end)
      assert serial_nos(result) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end
  end

  describe "a paginated read action" do
    test "with required pagination and a `default_limit` returns every record" do
      assert serial_nos(render(:all_keyset, %{})) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "with required pagination and no `default_limit` returns every record" do
      assert serial_nos(render(:all_keyset_no_default, %{})) ==
               ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "with offset pagination returns every record" do
      assert serial_nos(render(:all_offset, %{})) == ["A-1", "A-2", "A-3", "A-4", "A-5"]
    end

    test "is still subject to `limit`" do
      assert serial_nos(render(:limited_keyset, %{})) == ["A-1", "A-2", "A-3"]
    end

    test "works for a `:one` read" do
      assert printed(render(:one_keyset, %{serial_no: "A-2"})) == "A-2"
    end
  end

  describe "the read action" do
    test "`action` and `arguments` run another read action with render arguments" do
      assert serial_nos(render(:with_action_argument, %{where: "south"})) == ["A-2", "A-4"]
    end

    test "context set by a preparation of the render reaches the read action" do
      assert serial_nos(render(:with_preparation_context, %{where: "north"})) == ["A-1", "A-3"]
    end
  end

  describe "options from the caller" do
    setup do
      Ash.create!(Secured, %{serial_no: "S-1"})
      :ok
    end

    test "the read is authorized by default" do
      assert {:error, %Ash.Error.Forbidden{}} = render_secured(:render_all, [])
      assert {:error, %Ash.Error.Forbidden{}} = render_secured(:render_all_unstreamed, [])
      assert {:error, %Ash.Error.Forbidden{}} = render_secured(:render_first, [])
    end

    test "the caller's actor reaches the read" do
      assert serial_nos(render_secured(:render_all, actor: %{id: @alice})) == ["S-1"]
      assert printed(render_secured(:render_first, actor: %{id: @alice})) == "S-1"
    end

    test "`authorize?: false` reaches the read" do
      assert serial_nos(render_secured(:render_all, authorize?: false)) == ["S-1"]
      assert printed(render_secured(:render_first, authorize?: false)) == "S-1"
    end
  end

  describe "encoding_context" do
    test "is used for the record and the arguments of a `:one` read" do
      arguments = %{serial_no: "A-1", at: ~U[2026-01-01 12:00:00Z], timezone: "Asia/Tokyo"}

      assert printed(render(:shipped, arguments)) == "21 21"
    end

    test "is used for the records of a `:many` read" do
      assert printed(render(:shipped_many, %{})) == "21"
    end

    test "entries that resolve to `nil` are dropped" do
      arguments = %{serial_no: "A-1", at: ~U[2026-01-01 12:00:00Z]}

      assert printed(render(:shipped, arguments)) == "12 12"
    end
  end

  describe "not_found" do
    test "defaults to an error" do
      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               render(:one_by_and, %{packing_slip_no: "PS-1", serial_no: "A-4"})

      assert %Ash.Error.Query.NotFound{} = error
    end

    test "`:error` is an error" do
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               render(:one_explicit_error, %{serial_no: "nope"})
    end

    test "`nil` renders with `record` set to `none`" do
      assert printed(render(:one_or_none, %{serial_no: "nope"})) == "none"
      assert printed(render(:one_or_none, %{serial_no: "A-3"})) == "A-3"
    end
  end
end
