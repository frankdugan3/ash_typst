defmodule AshTypst.Resource.Transformers.ValidateFormatOptions do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.Info
  alias Spark.Dsl.{Entity, Transformer}
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    dsl_state
    |> Info.renders()
    |> Enum.each(fn render ->
      validate_page_option(render, module)
      validate_pdf_options(render, module)
      validate_read_options(render, module)
    end)

    {:ok, dsl_state}
  end

  defp validate_page_option(render, module) do
    if render.page && render.format != :svg do
      raise DslError,
        module: module,
        message:
          "Render #{inspect(render.name)}: `page` option is only valid when `format` is `:svg`, " <>
            "but format is #{inspect(render.format)}.",
        path: [:typst, render.name, :page],
        location: Entity.property_anno(render, :page) || Entity.anno(render)
    end
  end

  defp validate_pdf_options(render, module) do
    if render.pdf_options && render.format != :pdf do
      raise DslError,
        module: module,
        message:
          "Render #{inspect(render.name)}: `pdf_options` is only valid when `format` is `:pdf`, " <>
            "but format is #{inspect(render.format)}.",
        path: [:typst, render.name, :pdf_options],
        location: Entity.anno(render.pdf_options) || Entity.anno(render)
    end
  end

  defp validate_read_options(%{read: %{cardinality: :one} = read} = render, module) do
    reject(read.limit, render, read, :limit, "`read :one` does not support `limit`.", module)

    reject(
      read.batch_size && read.batch_size != 100,
      render,
      read,
      :batch_size,
      "`read :one` does not support `batch_size`.",
      module
    )

    reject(
      read.stream_with,
      render,
      read,
      :stream_with,
      "`read :one` does not support `stream_with`.",
      module
    )

    # `preflight?` defaults to `true`, so only an explicit `false` can be
    # told apart from the option not being set.
    reject(
      read.preflight? == false,
      render,
      read,
      :preflight?,
      "`read :one` does not support `preflight?`.",
      module
    )
  end

  # `not_found` defaults to `:error`, so only an explicit `nil` can be told
  # apart from the option not being set.
  defp validate_read_options(%{read: %{cardinality: :many} = read} = render, module) do
    reject(
      is_nil(read.not_found),
      render,
      read,
      :not_found,
      "`read :many` does not support `not_found`.",
      module
    )

    # Without streaming, all records are fetched and encoded at once.
    reject(
      read.stream_with == :none && read.batch_size != 100,
      render,
      read,
      :batch_size,
      "`stream_with :none` does not support `batch_size`.",
      module
    )

    # Without streaming, the template is compiled once, with all of the data.
    reject(
      read.stream_with == :none && read.preflight? == false,
      render,
      read,
      :preflight?,
      "`stream_with :none` does not support `preflight?`.",
      module
    )
  end

  defp validate_read_options(_render, _module), do: :ok

  defp reject(condition, _render, _read, _option, _message, _module)
       when condition in [nil, false],
       do: :ok

  defp reject(_condition, render, read, option, message, module) do
    raise DslError,
      module: module,
      message: "Render #{inspect(render.name)}: #{message}",
      path: [:typst, render.name, :read, option],
      location: Entity.property_anno(read, option) || Entity.anno(read)
  end
end
