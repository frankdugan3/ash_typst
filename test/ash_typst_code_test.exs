defmodule AshTypst.CodeTest do
  use ExUnit.Case
  doctest AshTypst.Code

  import Ash.Expr

  alias AshTypst.Test.CodeDerive.Resource

  describe "@derive AshTypst.Code" do
    test "opts an Ash resource struct into the protocol and encodes public fields" do
      record =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "Zardoz", secret: "p@ssw0rd"})
        |> Ash.create!()

      encoded = AshTypst.Code.encode(record, %{})

      assert encoded =~ ~s("id": "#{record.id}")
      assert encoded =~ ~s("name": "Zardoz")
      assert encoded =~ ~s("parent_id": none)
      refute encoded =~ "p@ssw0rd"
    end

    test "drops de-selected attributes entirely" do
      record =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "Zardoz"})
        |> Ash.create!()

      [reread] =
        Resource
        |> Ash.Query.filter_input(%{id: record.id})
        |> Ash.Query.select([:id])
        |> Ash.read!()

      encoded = AshTypst.Code.encode(reread, %{})

      assert encoded =~ ~s("id": "#{record.id}")
      refute encoded =~ "name"
    end

    test "drops not-loaded relationships and calculations, keeps loaded ones" do
      record =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "Zardoz"})
        |> Ash.create!()

      encoded = AshTypst.Code.encode(record, %{})

      refute encoded =~ ~s("parent": )
      refute encoded =~ "shout"

      loaded = Ash.load!(record, [:shout, :parent])
      encoded = AshTypst.Code.encode(loaded, %{})

      assert encoded =~ ~s("parent": none)
      assert encoded =~ ~s("shout": "Zardoz!")
    end

    test "drops empty calculations/aggregates maps, keeps anonymous calculations" do
      record =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "Zardoz"})
        |> Ash.create!()

      encoded = AshTypst.Code.encode(record, %{})

      refute encoded =~ "calculations"
      refute encoded =~ "aggregates"

      [reread] =
        Resource
        |> Ash.Query.filter_input(%{id: record.id})
        |> Ash.Query.calculate(:anon, :string, expr(name <> "?"))
        |> Ash.read!()

      encoded = AshTypst.Code.encode(reread, %{})

      assert encoded =~ ~s|"calculations": ("anon": "Zardoz?")|
      refute encoded =~ "aggregates"
    end

    test "drops forbidden fields silently" do
      record =
        Resource
        |> Ash.Changeset.for_create(:create, %{name: "Zardoz"})
        |> Ash.create!()

      redacted = %{record | name: %Ash.ForbiddenField{field: :name, type: :attribute}}

      encoded = AshTypst.Code.encode(redacted, %{})

      assert encoded =~ ~s("id": "#{record.id}")
      refute encoded =~ ~s("name")
      refute encoded =~ "Zardoz"
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
