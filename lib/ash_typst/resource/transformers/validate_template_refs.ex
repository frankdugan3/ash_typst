defmodule AshTypst.Resource.Transformers.ValidateTemplateRefs do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.{Info, Run}
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def after?(AshTypst.Resource.Transformers.BuildActions), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    templates =
      dsl_state
      |> Info.templates()
      |> MapSet.new(& &1.name)

    dsl_state
    |> Transformer.get_entities([:actions])
    |> Enum.each(fn
      %Ash.Resource.Actions.Action{run: {Run, opts}} ->
        template_name = opts[:template]

        if !MapSet.member?(templates, template_name) do
          raise DslError,
            module: Transformer.get_persisted(dsl_state, :module),
            message:
              "Action references template #{inspect(template_name)} " <>
                "but no template with that name is declared in the `typst` section. " <>
                "Declared templates: #{inspect(MapSet.to_list(templates))}",
            path: [:actions]
        end

      _ ->
        :ok
    end)

    {:ok, dsl_state}
  end
end
