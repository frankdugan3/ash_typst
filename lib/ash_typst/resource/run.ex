defmodule AshTypst.Resource.Run do
  @moduledoc false
  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Query.NotFound
  alias AshTypst.ContextPool
  alias AshTypst.Isolated
  alias AshTypst.Resource.Errors
  alias AshTypst.Resource.Info

  @impl true
  def run(input, opts, context) do
    resource = input.resource
    template = Info.template!(resource, opts[:template])

    template_opts = [
      actor: context.actor,
      tenant: context.tenant,
      args: input.arguments,
      context: input.context
    ]

    encoding_context =
      (opts[:encoding_context] || %{})
      |> Ash.Expr.fill_template(template_opts)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, data} <- fetch_data(resource, input, opts[:read], context, template_opts) do
      with_context(context_options(resource), data, opts[:isolate?], fn ctx ->
        render(ctx, template, resource, data, input, opts, encoding_context)
      end)
    end
  end

  # An isolated render runs in a peer node that exits afterwards, which
  # returns all of its memory to the OS.
  defp with_context(context_options, _data, true, fun) do
    Isolated.with_context(context_options, fun)
  rescue
    error in Isolated.Error -> {:error, error}
  end

  # A streamed render re-fetches its records every time, so nothing it
  # memoizes can be reused, and it is by far the largest render. Evict the
  # whole cache once the context is checked in (which drops the compiled
  # document), whether the render succeeded, failed or raised.
  defp with_context(context_options, {:many, _query, _stream_opts}, _isolate?, fun) do
    ContextPool.with_context(context_options, fun)
  after
    AshTypst.evict_cache()
  end

  defp with_context(context_options, _data, _isolate?, fun) do
    ContextPool.with_context(context_options, fun)
  end

  defp render(ctx, template, resource, data, input, opts, encoding_context) do
    with :ok <- set_template(ctx, template, resource),
         :ok <- set_inputs(ctx, template),
         :ok <- preflight(ctx, data, input.arguments, opts, encoding_context),
         :ok <- inject(ctx, data, input.arguments, opts, encoding_context),
         {:ok, compile_result} <- maybe_compile(ctx, opts[:format]) do
      export(ctx, opts[:format], opts, compile_result)
    end
  end

  # An isolated render streams its records from a task, so the heap that
  # fetching and encoding them grows is freed when the task exits instead of
  # staying with the caller, which may be long-lived. The task runs as the
  # caller (Ash reads the actor and tenant from the query and options) and
  # whatever it raises is raised again here.
  defp inject(ctx, {:many, _query, _stream_opts} = data, arguments, opts, encoding_context) do
    if opts[:isolate?] do
      fn ->
        try do
          {:ok, inject_data(ctx, data, arguments, opts, encoding_context)}
        catch
          kind, reason -> {:raise, kind, reason, __STACKTRACE__}
        end
      end
      |> Task.async()
      |> Task.await(:infinity)
      |> case do
        {:ok, result} -> result
        {:raise, kind, reason, stacktrace} -> :erlang.raise(kind, reason, stacktrace)
      end
    else
      inject_data(ctx, data, arguments, opts, encoding_context)
    end
  end

  defp inject(ctx, data, arguments, opts, encoding_context) do
    inject_data(ctx, data, arguments, opts, encoding_context)
  end

  # The bundle target uses `document`/`asset` elements that are invalid in the
  # paged target, and `export_bundle/2` compiles on its own (surfacing its own
  # warnings) — so skip the paged pre-compile for bundles.
  defp maybe_compile(_ctx, :bundle), do: {:ok, nil}

  defp maybe_compile(ctx, _format), do: compile(ctx)

  defp fetch_data(_resource, _input, nil, _context, _template_opts), do: {:ok, :none}

  defp fetch_data(resource, input, read, context, template_opts) do
    # The query carries the action context itself, see `build_query/5`.
    read_opts =
      context
      |> Ash.Scope.to_opts()
      |> Keyword.delete(:context)
      |> Keyword.put_new(:authorize?, true)

    query = build_query(resource, read, input, read_opts, template_opts)

    case read.cardinality do
      :one ->
        with {:ok, record} <- query |> Ash.read_one(read_opts) |> handle_not_found(read) do
          {:ok, {:one, record}}
        end

      :many when read.stream_with == :none ->
        with {:ok, records} <- Ash.read(query, Keyword.put(read_opts, :page, false)) do
          {:ok, {:all, records}}
        end

      :many ->
        stream_opts =
          Keyword.merge(read_opts,
            batch_size: read.batch_size,
            stream_with: read.stream_with
          )

        {:ok, {:many, query, stream_opts}}
    end
  end

  defp build_query(resource, read, input, read_opts, template_opts) do
    action = read.action || Ash.Resource.Info.primary_action!(resource, :read).name
    arguments = read.arguments |> Ash.Expr.fill_template(template_opts) |> Map.new()

    resource
    |> Ash.Query.new()
    |> Ash.Query.set_context(input.context)
    |> Ash.Query.for_read(action, arguments, read_opts)
    |> maybe_filter(read.filter, template_opts)
    |> maybe_load(read.load, template_opts)
    |> maybe_select(read.select)
    |> maybe_sort(read.sort, template_opts)
    |> maybe_limit(read.limit)
  end

  defp maybe_filter(query, nil, _template_opts), do: query

  defp maybe_filter(query, filter, template_opts) do
    Ash.Query.do_filter(query, Ash.Expr.fill_template(filter, template_opts))
  end

  defp maybe_load(query, [], _template_opts), do: query

  defp maybe_load(query, load, template_opts) do
    Ash.Query.load(query, Ash.Expr.fill_template(load, template_opts))
  end

  defp maybe_select(query, nil), do: query
  defp maybe_select(query, select), do: Ash.Query.select(query, select)

  defp maybe_sort(query, nil, _template_opts), do: query

  defp maybe_sort(query, sort, template_opts) do
    Ash.Query.sort(query, Ash.Expr.fill_template(sort, template_opts))
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: Ash.Query.limit(query, limit)

  # A template error only shows when the full data file is compiled, which
  # for a streamed read is after every record was fetched and encoded. So the
  # template is compiled against the first page first. `inject_data/5` then
  # overwrites the data file with the full stream. A bundle compiles only in
  # `export_bundle/2`, so it has no separate compile to run here.
  defp preflight(ctx, {:many, query, stream_opts}, arguments, opts, encoding_context) do
    if opts[:read][:preflight?] and opts[:format] != :bundle do
      with {:ok, records} <- first_page(query, stream_opts),
           :ok <- inject_data(ctx, {:all, records}, arguments, opts, encoding_context),
           {:ok, _compile_result} <- compile(ctx) do
        :ok
      end
    else
      :ok
    end
  end

  defp preflight(_ctx, _data, _arguments, _opts, _encoding_context), do: :ok

  # The same query as the stream, limited to one page. A page is requested
  # explicitly, because the action can require pagination.
  defp first_page(query, stream_opts) do
    limit = Enum.min(Enum.reject([stream_opts[:batch_size], query.limit], &is_nil/1))

    read_opts =
      stream_opts
      |> Keyword.drop([:batch_size, :stream_with])
      |> Keyword.put(:page, limit: limit)

    case Ash.read(query, read_opts) do
      {:ok, %{results: records}} -> {:ok, records}
      {:ok, records} when is_list(records) -> {:ok, records}
      {:error, error} -> {:error, error}
    end
  end

  defp handle_not_found({:ok, nil}, %{not_found: nil}), do: {:ok, nil}
  defp handle_not_found({:ok, nil}, _read), do: {:error, NotFound.exception([])}
  defp handle_not_found(result, _read), do: result

  defp context_options(resource) do
    {:ok, root} = Info.typst_root(resource)
    {:ok, font_paths} = Info.typst_font_paths(resource)
    {:ok, ignore_system_fonts} = Info.typst_ignore_system_fonts(resource)

    %AshTypst.Context.Options{
      root: AshTypst.PathResolver.resolve(root),
      font_paths: AshTypst.PathResolver.resolve_all(font_paths),
      ignore_system_fonts: ignore_system_fonts
    }
  end

  defp set_template(ctx, %{source: source}, resource) when not is_nil(source) do
    {:ok, root} = Info.typst_root(resource)
    path = Path.join(AshTypst.PathResolver.resolve(root), source)

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

  defp inject_data(ctx, :none, arguments, opts, encoding_context) do
    AshTypst.Context.set_virtual_file(
      ctx,
      opts[:data_file] || "data.typ",
      args_code(arguments, encoding_context)
    )
  end

  defp inject_data(ctx, {:one, record}, arguments, opts, encoding_context) do
    data =
      "#let record = #{AshTypst.Code.encode(record, encoding_context)}\n" <>
        args_code(arguments, encoding_context)

    AshTypst.Context.set_virtual_file(ctx, opts[:data_file] || "data.typ", data)
  end

  # `stream_with :none`: the records were read in one go, so encode them in one go.
  defp inject_data(ctx, {:all, records}, arguments, opts, encoding_context) do
    data =
      "#let records = #{AshTypst.Code.encode(records, encoding_context)}\n" <>
        args_code(arguments, encoding_context)

    AshTypst.Context.set_virtual_file(ctx, opts[:data_file] || "data.typ", data)
  end

  defp inject_data(ctx, {:many, query, stream_opts}, arguments, opts, encoding_context) do
    data_file = opts[:data_file] || "data.typ"

    with :ok <-
           AshTypst.Context.stream_virtual_file(ctx, data_file, Ash.stream!(query, stream_opts),
             variable_name: "records",
             context: encoding_context,
             batch_size: stream_opts[:batch_size]
           ) do
      AshTypst.Context.append_virtual_file(
        ctx,
        data_file,
        args_code(arguments, encoding_context)
      )
    end
  rescue
    # `Ash.stream!/2` raises, both up front and while the records are consumed.
    error ->
      if Ash.Error.ash_error?(error) do
        {:error, error}
      else
        reraise error, __STACKTRACE__
      end
  end

  defp args_code(arguments, encoding_context) do
    "#let args = #{AshTypst.Code.encode(Map.new(arguments), encoding_context)}\n"
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
    svg_opts = [
      page: opts[:page] || 0,
      pretty: opts[:pretty] || false,
      render_bleed: opts[:render_bleed] || false
    ]

    with {:ok, data} <- AshTypst.Context.render_svg(ctx, svg_opts) do
      {:ok,
       %AshTypst.Document{
         format: :svg,
         data: data,
         page_count: compile_result.page_count,
         warnings: compile_result.warnings
       }}
    end
  end

  defp export(ctx, :html, opts, compile_result) do
    with {:ok, data} <- AshTypst.Context.export_html(ctx, pretty: opts[:pretty] || false) do
      {:ok,
       %AshTypst.Document{
         format: :html,
         data: data,
         page_count: compile_result.page_count,
         warnings: compile_result.warnings
       }}
    end
  end

  defp export(ctx, :bundle, opts, _compile_result) do
    bundle_opts = [
      pretty: opts[:pretty] || false,
      render_bleed: opts[:render_bleed] || false
    ]

    with {:ok, %AshTypst.BundleResult{files: files, warnings: warnings}} <-
           AshTypst.Context.export_bundle(ctx, bundle_opts) do
      {:ok,
       %AshTypst.Document{
         format: :bundle,
         data: files,
         page_count: nil,
         warnings: warnings
       }}
    end
  end
end
