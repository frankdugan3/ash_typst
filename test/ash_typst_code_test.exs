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
      # Private fields are excluded.
      refute encoded =~ "p@ssw0rd"
    end
  end
end
