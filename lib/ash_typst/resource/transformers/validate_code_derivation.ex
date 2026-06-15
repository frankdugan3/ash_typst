defmodule AshTypst.Resource.Transformers.ValidateCodeDerivation do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.Info
  alias Spark.Dsl.{Entity, Transformer}
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    reading_render =
      dsl_state
      |> Info.renders()
      |> Enum.find(& &1.read)

    if reading_render && not implements_code?(module) do
      raise DslError,
        module: module,
        message:
          "Render #{inspect(reading_render.name)} declares a `read`, so the fetched " <>
            "records are encoded via the `AshTypst.Code` protocol, but #{inspect(module)} " <>
            "does not implement it.\n\n" <>
            "Add `@derive AshTypst.Code` to the resource to use the built-in implementation " <>
            "(which serializes the resource's public fields), or implement the protocol " <>
            "directly with `defimpl AshTypst.Code, for: #{inspect(module)}`.",
        path: [:typst, reading_render.name, :read],
        location: Entity.anno(reading_render.read) || Entity.anno(reading_render)
    end

    {:ok, dsl_state}
  end

  defp implements_code?(module) do
    derived?(module) or
      match?({:module, _}, Code.ensure_compiled(Module.concat(AshTypst.Code, module)))
  end

  defp derived?(module) do
    module
    |> Module.get_attribute(:derive, [])
    |> List.wrap()
    |> Enum.any?(&derives_code?/1)
  end

  defp derives_code?(AshTypst.Code), do: true
  defp derives_code?({AshTypst.Code, _opts}), do: true
  defp derives_code?(list) when is_list(list), do: Enum.any?(list, &derives_code?/1)
  defp derives_code?(_), do: false
end
