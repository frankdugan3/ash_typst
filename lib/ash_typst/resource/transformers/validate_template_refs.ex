defmodule AshTypst.Resource.Transformers.ValidateTemplateRefs do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.Info
  alias Spark.Dsl.{Entity, Transformer}
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    template_names =
      dsl_state
      |> Info.templates()
      |> MapSet.new(& &1.name)

    dsl_state
    |> Info.renders()
    |> Enum.each(fn render ->
      unless MapSet.member?(template_names, render.template) do
        raise DslError,
          module: module,
          message:
            "Render #{inspect(render.name)} references template #{inspect(render.template)} " <>
              "but no template with that name is declared in the `typst` section. " <>
              "Declared templates: #{inspect(MapSet.to_list(template_names))}",
          path: [:typst, render.name, :template],
          location: Entity.property_anno(render, :template) || Entity.anno(render)
      end
    end)

    {:ok, dsl_state}
  end
end
