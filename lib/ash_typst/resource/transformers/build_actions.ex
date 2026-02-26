defmodule AshTypst.Resource.Transformers.BuildActions do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    render_entities =
      dsl_state
      |> Transformer.get_entities([:typst])
      |> Enum.filter(&match?(%AshTypst.Resource.Render{}, &1))

    dsl_state =
      Enum.reduce(render_entities, dsl_state, fn entity, dsl_state ->
        action = build_action(entity)
        Transformer.add_entity(dsl_state, [:actions], action)
      end)

    {:ok, dsl_state}
  end

  defp build_action(entity) do
    # With singleton_entity_keys, read and pdf_options are a single entity or nil
    read_entity = entity.read
    pdf_options_entity = entity.pdf_options

    run_opts =
      [
        template: entity.template,
        format: entity.format,
        data_file: entity.data_file,
        page: entity.page
      ]
      |> then(fn opts ->
        if read_entity do
          Keyword.put(opts, :read, Map.from_struct(read_entity))
        else
          opts
        end
      end)
      |> then(fn opts ->
        if pdf_options_entity do
          Keyword.put(opts, :pdf_options, Map.from_struct(pdf_options_entity))
        else
          opts
        end
      end)

    %Ash.Resource.Actions.Action{
      name: entity.name,
      description: entity.description,
      returns: AshTypst.Type.Document,
      run: {AshTypst.Resource.Run, run_opts},
      arguments: entity.arguments,
      preparations: entity.preparations,
      transaction?: entity.transaction?,
      type: :action,
      __spark_metadata__: entity.__spark_metadata__
    }
  end
end
