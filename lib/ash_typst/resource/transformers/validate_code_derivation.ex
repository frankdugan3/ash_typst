defmodule AshTypst.Resource.Transformers.ValidateCodeDerivation do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.Run
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def after?(AshTypst.Resource.Transformers.BuildActions), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    reading_action =
      dsl_state
      |> Transformer.get_entities([:actions])
      |> Enum.find(fn
        %Ash.Resource.Actions.Action{run: {Run, opts}} -> not is_nil(opts[:read])
        _ -> false
      end)

    if reading_action && not implements_code?(module) do
      raise DslError,
        module: module,
        message:
          "Action #{inspect(reading_action.name)} declares a `read`, so the fetched " <>
            "records are encoded via the `AshTypst.Code` protocol, but #{inspect(module)} " <>
            "does not implement it.\n\n" <>
            "Add `@derive AshTypst.Code` to the resource to use the built-in implementation " <>
            "(which serializes the resource's public fields), or implement the protocol " <>
            "directly with `defimpl AshTypst.Code, for: #{inspect(module)}`.",
        path: [:typst]
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
