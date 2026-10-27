defmodule AshTypst.Resource.Transformers.ValidateRead do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.Info
  alias Spark.Dsl.{Entity, Transformer}
  alias Spark.Error.DslError

  # The read action may come from `defaults`, which Ash expands in a transformer.
  @impl true
  def after?(_), do: true

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    dsl_state
    |> Info.renders()
    |> Enum.each(&validate_render(&1, dsl_state, module))

    {:ok, dsl_state}
  end

  defp validate_render(render, dsl_state, module) do
    validate_arg_refs(render, render, :encoding_context, module)

    if render.read do
      for option <- [:filter, :load, :sort, :arguments] do
        validate_arg_refs(render, render.read, option, module)
      end

      validate_action(render, render.read, dsl_state, module)
    end
  end

  defp validate_arg_refs(render, entity, option, module) do
    declared = Enum.map(render.arguments, &to_string(&1.name))

    entity
    |> Map.fetch!(option)
    |> arg_refs()
    |> Enum.reject(&(to_string(&1) in declared))
    |> case do
      [] ->
        :ok

      [name | _] ->
        raise DslError,
          module: module,
          message:
            "Render #{inspect(render.name)}: `#{option}` references argument #{inspect(name)}, " <>
              "but the render action declares no argument with that name. " <>
              "Declared arguments: #{inspect(Enum.map(render.arguments, & &1.name))}",
          path: option_path(render, entity, option),
          location: Entity.property_anno(entity, option) || Entity.anno(entity)
    end
  end

  # Walks the template the same way `Ash.Expr.fill_template/2` does, so every
  # reference that is resolved at run time is seen here.
  defp arg_refs(template) do
    key = {__MODULE__, :arg_refs}
    Process.put(key, [])

    Ash.Expr.walk_template(template, fn
      {:_arg, name} = ref ->
        Process.put(key, [name | Process.get(key)])
        ref

      other ->
        other
    end)

    key |> Process.delete() |> Enum.reverse()
  end

  defp validate_action(render, read, dsl_state, module) do
    action =
      if read.action do
        Ash.Resource.Info.action(dsl_state, read.action)
      else
        Ash.Resource.Info.primary_action(dsl_state, :read)
      end

    case action do
      %{type: :read} ->
        validate_action_arguments(render, read, action, module)
        validate_pagination(render, read, action, module)

      nil when is_nil(read.action) ->
        raise DslError,
          module: module,
          message:
            "Render #{inspect(render.name)} declares a `read`, but #{inspect(module)} has no " <>
              "primary read action. Add one, or set `action` on the `read`.",
          path: [:typst, render.name, :read],
          location: Entity.anno(read)

      nil ->
        raise DslError,
          module: module,
          message:
            "Render #{inspect(render.name)}: `read` uses action #{inspect(read.action)}, " <>
              "but #{inspect(module)} has no action with that name.",
          path: [:typst, render.name, :read, :action],
          location: Entity.property_anno(read, :action) || Entity.anno(read)

      %{type: type} ->
        raise DslError,
          module: module,
          message:
            "Render #{inspect(render.name)}: `read` uses action #{inspect(read.action)}, " <>
              "but its type is #{inspect(type)}. Only read actions are supported.",
          path: [:typst, render.name, :read, :action],
          location: Entity.property_anno(read, :action) || Entity.anno(read)
    end
  end

  defp validate_action_arguments(render, read, action, module) do
    accepted = Enum.map(action.arguments, &to_string(&1.name))

    read.arguments
    |> Enum.map(&elem(&1, 0))
    |> Enum.reject(&(to_string(&1) in accepted))
    |> case do
      [] ->
        :ok

      [name | _] ->
        raise DslError,
          module: module,
          message:
            "Render #{inspect(render.name)}: `arguments` sets #{inspect(name)}, but read action " <>
              "#{inspect(action.name)} accepts no argument with that name. " <>
              "Accepted arguments: #{inspect(Enum.map(action.arguments, & &1.name))}",
          path: [:typst, render.name, :read, :arguments],
          location: Entity.property_anno(read, :arguments) || Entity.anno(read)
    end
  end

  # `read :many` is streamed page by page, which needs pagination on the action,
  # unless streaming is turned off explicitly with `stream_with :none`.
  defp validate_pagination(_render, %{cardinality: :one}, _action, _module), do: :ok

  defp validate_pagination(render, %{stream_with: nil} = read, action, module) do
    if not supports?(action, :keyset) and not supports?(action, :offset) do
      raise DslError,
        module: module,
        message:
          "Render #{inspect(render.name)}: `read :many` streams its records page by page, " <>
            "but read action #{inspect(action.name)} has no pagination. Add " <>
            "`pagination keyset?: true, required?: false` to the action, or set " <>
            "`stream_with :none` on the `read` to read every record at once.",
        path: [:typst, render.name, :read, :action],
        location: Entity.property_anno(read, :action) || Entity.anno(read)
    end
  end

  defp validate_pagination(render, %{stream_with: :none} = read, action, module) do
    if match?(%{pagination: %{required?: true}}, action) do
      supported =
        [:keyset, :offset]
        |> Enum.filter(&supports?(action, &1))
        |> Enum.map_join(" or ", &"`stream_with #{inspect(&1)}`")

      raise DslError,
        module: module,
        message:
          "Render #{inspect(render.name)}: `stream_with :none` reads every record in one " <>
            "unpaginated read, but read action #{inspect(action.name)} requires pagination. " <>
            "Stream the records with #{supported} instead.",
        path: [:typst, render.name, :read, :stream_with],
        location: Entity.property_anno(read, :stream_with) || Entity.anno(read)
    end
  end

  defp validate_pagination(render, read, action, module) do
    if not supports?(action, read.stream_with) do
      raise DslError,
        module: module,
        message:
          "Render #{inspect(render.name)}: `stream_with #{inspect(read.stream_with)}` needs " <>
            "#{read.stream_with} pagination, but read action #{inspect(action.name)} does not " <>
            "support it. Add `#{read.stream_with}?: true` to the action's `pagination`, or " <>
            "set `stream_with :none` to read every record at once.",
        path: [:typst, render.name, :read, :stream_with],
        location: Entity.property_anno(read, :stream_with) || Entity.anno(read)
    end
  end

  defp supports?(%{pagination: %{keyset?: true}}, :keyset), do: true
  defp supports?(%{pagination: %{offset?: true}}, :offset), do: true
  defp supports?(_action, _type), do: false

  defp option_path(render, render, option), do: [:typst, render.name, option]
  defp option_path(render, _read, option), do: [:typst, render.name, :read, option]
end
