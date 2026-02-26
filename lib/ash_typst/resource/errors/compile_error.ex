defmodule AshTypst.Resource.Errors.CompileError do
  @moduledoc "Ash-compatible error wrapping Typst compilation diagnostics."
  use Splode.Error, fields: [:diagnostics], class: :invalid

  def message(%{diagnostics: diagnostics}) when is_list(diagnostics) do
    messages =
      Enum.map_join(diagnostics, "\n", fn
        %AshTypst.Diagnostic{message: msg, span: span} ->
          case span do
            %AshTypst.Span{line: line, column: col} when not is_nil(line) ->
              "  #{line}:#{col} #{msg}"

            _ ->
              "  #{msg}"
          end

        other ->
          "  #{inspect(other)}"
      end)

    "Typst compilation failed:\n#{messages}"
  end

  def message(_), do: "Typst compilation failed"

  @doc false
  @spec from(AshTypst.CompileError.t()) :: Exception.t()
  def from(%AshTypst.CompileError{diagnostics: diagnostics}) do
    %__MODULE__{diagnostics: diagnostics}
  end
end
