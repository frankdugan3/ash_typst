defmodule AshTypst.Resource.Verifiers.ValidateTemplateRefs do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    templates =
      dsl_state
      |> AshTypst.Resource.Info.templates()
      |> MapSet.new(& &1.name)

    dsl_state
    |> Spark.Dsl.Extension.get_entities([:actions])
    |> Enum.each(fn
      %Ash.Resource.Actions.Action{run: {AshTypst.Resource.Run, opts}} ->
        template_name = opts[:template]

        if !MapSet.member?(templates, template_name) do
          raise DslError,
            module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module),
            message:
              "Action references template #{inspect(template_name)} " <>
                "but no template with that name is declared in the `typst` section. " <>
                "Declared templates: #{inspect(MapSet.to_list(templates))}",
            path: [:actions]
        end

      _ ->
        :ok
    end)
  end
end
