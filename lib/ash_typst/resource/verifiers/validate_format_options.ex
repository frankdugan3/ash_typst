defmodule AshTypst.Resource.Verifiers.ValidateFormatOptions do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias AshTypst.Resource.Run
  alias Spark.Dsl.{Extension, Verifier}
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    dsl_state
    |> Extension.get_entities([:actions])
    |> Enum.each(fn
      %Ash.Resource.Actions.Action{run: {Run, opts}} = action ->
        validate_page_option(opts, action, module)
        validate_pdf_options(opts, action, module)
        validate_read_options(opts, action, module)

      _ ->
        :ok
    end)
  end

  defp validate_page_option(opts, action, module) do
    if opts[:page] && opts[:format] != :svg do
      raise DslError,
        module: module,
        message:
          "Action #{inspect(action.name)}: `page` option is only valid when `format` is `:svg`, " <>
            "but format is #{inspect(opts[:format])}.",
        path: [:actions, action.name]
    end
  end

  defp validate_pdf_options(opts, action, module) do
    if opts[:pdf_options] && opts[:format] != :pdf do
      raise DslError,
        module: module,
        message:
          "Action #{inspect(action.name)}: `pdf_options` is only valid when `format` is `:pdf`, " <>
            "but format is #{inspect(opts[:format])}.",
        path: [:actions, action.name]
    end
  end

  defp validate_read_options(opts, action, module) do
    case opts[:read] do
      %{cardinality: :one} = read ->
        if read[:limit] do
          raise DslError,
            module: module,
            message: "Action #{inspect(action.name)}: `read :one` does not support `limit`.",
            path: [:actions, action.name, :read]
        end

        if read[:batch_size] && read[:batch_size] != 100 do
          raise DslError,
            module: module,
            message: "Action #{inspect(action.name)}: `read :one` does not support `batch_size`.",
            path: [:actions, action.name, :read]
        end

      %{cardinality: :many} = read ->
        if read[:not_found] do
          raise DslError,
            module: module,
            message: "Action #{inspect(action.name)}: `read :many` does not support `not_found`.",
            path: [:actions, action.name, :read]
        end

      _ ->
        :ok
    end
  end
end
