defmodule AshTypst.Resource.Run do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Query.NotFound
  alias AshTypst.Resource.Errors
  alias AshTypst.Resource.Info

  require Ash.Query

  @impl true
  def run(input, opts, context) do
    resource = input.resource
    template = Info.template!(resource, opts[:template])

    with {:ok, data} <- fetch_data(resource, input, opts, context),
         {:ok, ctx} <- build_context(resource),
         :ok <- set_template(ctx, template, resource),
         :ok <- set_inputs(ctx, template),
         :ok <- inject_data(ctx, data, input.arguments, opts),
         {:ok, compile_result} <- compile(ctx) do
      export(ctx, opts[:format], opts, compile_result)
    end
  end

  defp fetch_data(_resource, _input, opts, _context) when not is_map_key(opts, :read) do
    {:ok, nil}
  end

  defp fetch_data(resource, input, opts, context) do
    case opts[:read] do
      nil ->
        {:ok, nil}

      read ->
        query =
          resource
          |> Ash.Query.new()
          |> apply_read_opts(read, input)
          |> merge_preparation_context(input)

        read_opts = [
          actor: context.actor,
          tenant: context.tenant,
          authorize?: true
        ]

        case read.cardinality do
          :one ->
            query
            |> Ash.read_one(read_opts)
            |> handle_not_found(read)

          :many ->
            Ash.read(query, read_opts)
        end
    end
  end

  defp apply_read_opts(query, read, input) do
    query
    |> maybe_filter(read.filter, input)
    |> maybe_load(read.load)
    |> maybe_select(read[:select])
    |> maybe_sort(read[:sort])
    |> maybe_limit(read[:limit])
  end

  defp maybe_filter(query, nil, _input), do: query

  defp maybe_filter(query, filter, _input) do
    Ash.Query.do_filter(query, filter)
  end

  defp maybe_load(query, []), do: query
  defp maybe_load(query, load), do: Ash.Query.load(query, load)

  defp maybe_select(query, nil), do: query
  defp maybe_select(query, select), do: Ash.Query.select(query, select)

  defp maybe_sort(query, nil), do: query
  defp maybe_sort(query, sort), do: Ash.Query.sort(query, sort)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: Ash.Query.limit(query, limit)

  defp merge_preparation_context(query, input) do
    case input.context do
      %{} = ctx when map_size(ctx) > 0 -> Ash.Query.set_context(query, ctx)
      _ -> query
    end
  end

  defp handle_not_found({:ok, nil}, %{not_found: :error}) do
    {:error, NotFound.exception([])}
  end

  defp handle_not_found({:ok, nil}, %{not_found: nil}), do: {:ok, nil}
  defp handle_not_found({:ok, nil}, _), do: {:error, NotFound.exception([])}
  defp handle_not_found(result, _), do: result

  defp build_context(resource) do
    {:ok, root} = Info.typst_root(resource)
    {:ok, font_paths} = Info.typst_font_paths(resource)
    {:ok, ignore_system_fonts} = Info.typst_ignore_system_fonts(resource)

    AshTypst.Context.new(
      root: root,
      font_paths: font_paths,
      ignore_system_fonts: ignore_system_fonts
    )
  end

  defp set_template(ctx, %{source: source}, resource) when not is_nil(source) do
    {:ok, root} = Info.typst_root(resource)
    path = Path.join(root, source)

    case File.read(path) do
      {:ok, markup} -> AshTypst.Context.set_markup(ctx, markup)
      {:error, reason} -> {:error, "Failed to read template file #{path}: #{inspect(reason)}"}
    end
  end

  defp set_template(ctx, %{markup: markup}, _resource) when not is_nil(markup) do
    AshTypst.Context.set_markup(ctx, markup)
  end

  defp set_inputs(_ctx, %{inputs: nil}), do: :ok
  defp set_inputs(_ctx, %{inputs: inputs}) when map_size(inputs) == 0, do: :ok

  defp set_inputs(ctx, %{inputs: inputs}) do
    AshTypst.Context.set_inputs(ctx, inputs)
  end

  defp inject_data(ctx, nil, arguments, opts) do
    data = "#let args = #{AshTypst.Code.encode(Map.new(arguments))}\n"
    AshTypst.Context.set_virtual_file(ctx, opts[:data_file] || "data.typ", data)
  end

  defp inject_data(ctx, record, arguments, opts) when not is_list(record) do
    data =
      "#let record = #{AshTypst.Code.encode(record)}\n" <>
        "#let args = #{AshTypst.Code.encode(Map.new(arguments))}\n"

    AshTypst.Context.set_virtual_file(ctx, opts[:data_file] || "data.typ", data)
  end

  defp inject_data(ctx, records, arguments, opts) when is_list(records) do
    data_file = opts[:data_file] || "data.typ"
    batch_size = get_in(opts, [:read, :batch_size]) || 100

    AshTypst.Context.stream_virtual_file(ctx, data_file, records,
      variable_name: "records",
      batch_size: batch_size
    )

    args_code = "#let args = #{AshTypst.Code.encode(Map.new(arguments))}\n"
    AshTypst.Context.append_virtual_file(ctx, data_file, args_code)
  end

  defp compile(ctx) do
    case AshTypst.Context.compile(ctx) do
      {:ok, result} ->
        {:ok, result}

      {:error, compile_error} ->
        {:error, Errors.CompileError.from(compile_error)}
    end
  end

  defp export(ctx, :pdf, opts, compile_result) do
    pdf_opts =
      case opts[:pdf_options] do
        nil ->
          []

        map when is_map(map) ->
          map
          |> Map.delete(:__spark_metadata__)
          |> Map.delete(:__identifier__)
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      end

    with {:ok, data} <- AshTypst.Context.export_pdf(ctx, pdf_opts) do
      {:ok,
       %AshTypst.Document{
         format: :pdf,
         data: data,
         page_count: compile_result.page_count,
         warnings: compile_result.warnings
       }}
    end
  end

  defp export(ctx, :svg, opts, compile_result) do
    with {:ok, data} <- AshTypst.Context.render_svg(ctx, page: opts[:page] || 0) do
      {:ok,
       %AshTypst.Document{
         format: :svg,
         data: data,
         page_count: compile_result.page_count,
         warnings: compile_result.warnings
       }}
    end
  end

  defp export(ctx, :html, _opts, compile_result) do
    with {:ok, data} <- AshTypst.Context.export_html(ctx) do
      {:ok,
       %AshTypst.Document{
         format: :html,
         data: data,
         page_count: compile_result.page_count,
         warnings: compile_result.warnings
       }}
    end
  end
end
