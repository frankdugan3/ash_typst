defmodule AshTypst.PathResolverTest do
  use ExUnit.Case, async: true

  alias AshTypst.PathResolver

  describe "resolve/1" do
    test "passes string paths through verbatim" do
      assert PathResolver.resolve("priv/typst") == "priv/typst"
      assert PathResolver.resolve("/absolute/path") == "/absolute/path"
    end

    test "resolves {otp_app, sub_path} via Application.app_dir/2" do
      result = PathResolver.resolve({:ash_typst, "priv/typst"})

      assert is_binary(result)
      assert Path.type(result) == :absolute
      assert String.ends_with?(result, "priv/typst")
    end

    test "supports nested sub_paths in tuple form" do
      result = PathResolver.resolve({:ash_typst, "priv/foo/bar"})

      assert String.ends_with?(result, "priv/foo/bar")
    end

    test "raises if otp_app is not loaded" do
      assert_raise ArgumentError, fn ->
        PathResolver.resolve({:nonexistent_app_xyz_12345, "priv"})
      end
    end
  end

  describe "resolve_all/1" do
    test "resolves a list of mixed string + tuple entries" do
      result =
        PathResolver.resolve_all([
          "priv/fonts",
          {:ash_typst, "priv/fonts"}
        ])

      assert [first, second] = result
      assert first == "priv/fonts"
      assert String.ends_with?(second, "priv/fonts")
      assert Path.type(second) == :absolute
    end

    test "returns empty list for empty input" do
      assert PathResolver.resolve_all([]) == []
    end
  end
end
