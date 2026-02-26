defmodule AshTypst.Resource.Info do
  @moduledoc """
  Introspection functions for the `AshTypst.Resource` extension.

  Use these functions to programmatically inspect the templates, render entities,
  and configuration options declared in a resource's `typst` DSL section.

  For the full DSL reference, see `d:AshTypst.Resource`.
  """

  use Spark.InfoGenerator, extension: AshTypst.Resource, sections: [:typst]

  alias AshTypst.Resource.{Render, Template}
  alias Spark.Dsl.Extension

  @doc "Returns all templates declared in the `typst` section."
  @spec templates(Spark.Dsl.t() | module()) :: [Template.t()]
  def templates(resource) do
    resource
    |> Extension.get_entities([:typst])
    |> Enum.filter(&match?(%Template{}, &1))
  end

  @doc "Returns all render entities declared in the `typst` section."
  @spec renders(Spark.Dsl.t() | module()) :: [Render.t()]
  def renders(resource) do
    resource
    |> Extension.get_entities([:typst])
    |> Enum.filter(&match?(%Render{}, &1))
  end

  @doc "Looks up a template by name. Returns `{:ok, template}` or `:error`."
  @spec template(Spark.Dsl.t() | module(), atom()) ::
          {:ok, AshTypst.Resource.Template.t()} | :error
  def template(resource, name) do
    case Enum.find(templates(resource), &(&1.name == name)) do
      nil -> :error
      template -> {:ok, template}
    end
  end

  @doc "Looks up a template by name. Raises if not found."
  @spec template!(Spark.Dsl.t() | module(), atom()) :: AshTypst.Resource.Template.t()
  def template!(resource, name) do
    case template(resource, name) do
      {:ok, template} ->
        template

      :error ->
        raise ArgumentError, "No template named #{inspect(name)} found on #{inspect(resource)}"
    end
  end
end
