defmodule AshTypst.Resource.Transformers.ValidateTemplateSources do
  @moduledoc false
  # Checks the Typst syntax of file-based templates (`source`) at compile time,
  # the same check the `~TYPST` sigil runs on inline markup. The template file
  # is only parsed, so imports and other render-time dependencies need not
  # exist. Each template file is also registered as an `@external_resource`, so
  # editing it recompiles the resource and re-runs the check.
  use Spark.Dsl.Transformer

  alias AshTypst.Resource.Info
  alias AshTypst.SyntaxReport
  alias Spark.Dsl.{Entity, Transformer}
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)
    root = Transformer.get_option(dsl_state, [:typst], :root, "priv/typst")
    roots = resolve_root(root)

    {dsl_state, warnings} =
      dsl_state
      |> Info.templates()
      |> Enum.reject(&is_nil(&1.source))
      |> Enum.reduce({dsl_state, []}, fn template, {dsl_state, warnings} ->
        location = Entity.property_anno(template, :source) || Entity.anno(template)
        path = roots |> Enum.map(&Path.join(&1, template.source)) |> find_file()

        case path && File.read(path) do
          {:ok, markup} ->
            new_warnings = validate!(markup, path, template, module, location)
            {add_external_resource(dsl_state, path), warnings ++ new_warnings}

          _ ->
            message =
              "Template #{inspect(template.name)}: `source` file #{inspect(template.source)} " <>
                "was not found in root #{inspect(root)} at compile time, " <>
                "so its Typst syntax was not checked."

            {dsl_state, warnings ++ [{message, location}]}
        end
      end)

    case warnings do
      [] -> {:ok, dsl_state}
      warnings -> {:warn, dsl_state, warnings}
    end
  end

  defp validate!(markup, path, template, module, location) do
    origin = SyntaxReport.file_origin()
    {errors, warnings} = SyntaxReport.diagnostics(markup)

    # Only the first error: the ones after it are mostly its echoes
    # (`SyntaxReport.first_error/1`).
    if error = SyntaxReport.first_error(errors) do
      report = SyntaxReport.format(error, markup, origin, path)

      raise DslError,
        module: module,
        # Spark indents the first line of the message under the DSL path;
        # indent the report to match.
        message:
          "Template #{inspect(template.name)}: `source` file has invalid Typst syntax.\n\n" <>
            indent(report),
        path: [:typst, template.name, :source],
        location: location
    end

    for warning <- warnings do
      {"Template #{inspect(template.name)}: `source` file has a Typst syntax warning.\n\n" <>
         SyntaxReport.format(warning, markup, origin, path), location}
    end
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> "  " <> line
    end)
  end

  # `root` is resolved again at runtime (see `AshTypst.PathResolver`). At
  # compile time an `{otp_app, sub_path}` root of the app being compiled may
  # not be reachable through `Application.app_dir/2` yet, so fall back to the
  # sub path relative to the project being compiled (the working directory).
  defp resolve_root(root) when is_binary(root), do: [root]

  defp resolve_root({_otp_app, sub_path} = root) do
    app_dir =
      try do
        [AshTypst.PathResolver.resolve(root)]
      rescue
        ArgumentError -> []
      end

    app_dir ++ [Path.join(File.cwd!(), sub_path)]
  end

  defp find_file(candidates), do: Enum.find(candidates, &File.regular?/1)

  defp add_external_resource(dsl_state, path) do
    Transformer.eval(
      dsl_state,
      [],
      quote do
        @external_resource unquote(path)
      end
    )
  end
end
