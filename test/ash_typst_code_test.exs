defmodule AshTypst.CodeTest do
  use ExUnit.Case
  doctest AshTypst.Code

  alias AshTypst.Test.CodeDerive.Resource

  describe "@derive AshTypst.Code" do
    test "opts an Ash resource struct into the protocol and encodes public fields" do
      record =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "Zardoz", secret: "p@ssw0rd"})
        |> Ash.create!()

      encoded = AshTypst.Code.encode(record, %{})

      assert encoded =~ ~s("name": "Zardoz")
      refute encoded =~ "p@ssw0rd"
    end
  end

  describe "Decimal" do
    test "encodes via the string constructor to preserve precision" do
      assert AshTypst.Code.encode(Decimal.new("3.14"), %{}) == "decimal(\"3.14\")"
    end
  end

  describe "generated code compiles under the bundled Typst" do
    test "representative values compile without errors or warnings" do
      values = %{
        list: ["one", 2, 3.0],
        datetime: ~U[2015-01-13 13:00:07Z],
        date: ~D[2024-06-15],
        time: ~T[09:30:00],
        decimal: Decimal.new("3.14"),
        float: 3.5,
        int: 42,
        string: "he said \"hi\"\nnewline\ttab",
        bool: true,
        none: nil,
        empty_map: %{},
        empty_list: []
      }

      markup = "#let data = #{AshTypst.Code.encode(values, %{})}\n#data.decimal"

      {:ok, ctx} = AshTypst.Context.new()
      assert :ok = AshTypst.Context.set_markup(ctx, markup)
      assert {:ok, %{warnings: []}} = AshTypst.Context.compile(ctx)
    end
  end
end
