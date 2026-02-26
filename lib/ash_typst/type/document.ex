defmodule AshTypst.Type.Document do
  @moduledoc "Custom Ash type for `%AshTypst.Document{}`."
  use Ash.Type

  @impl true
  def storage_type(_), do: :map

  @impl true
  def cast_input(%AshTypst.Document{} = doc, _), do: {:ok, doc}
  def cast_input(nil, _), do: {:ok, nil}

  def cast_input(%{} = map, _) do
    {:ok,
     %AshTypst.Document{
       format: to_existing_atom(map[:format] || map["format"]),
       data: map[:data] || map["data"],
       page_count: map[:page_count] || map["page_count"],
       warnings: map[:warnings] || map["warnings"] || []
     }}
  end

  def cast_input(_, _), do: :error

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}

  def cast_stored(%{} = map, _) do
    {:ok,
     %AshTypst.Document{
       format: to_existing_atom(map[:format] || map["format"]),
       data: map[:data] || map["data"],
       page_count: map[:page_count] || map["page_count"],
       warnings: map[:warnings] || map["warnings"] || []
     }}
  end

  def cast_stored(_, _), do: :error

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}

  def dump_to_native(%AshTypst.Document{} = doc, _) do
    {:ok,
     %{
       format: to_string(doc.format),
       data: doc.data,
       page_count: doc.page_count,
       warnings: doc.warnings
     }}
  end

  def dump_to_native(_, _), do: :error

  @impl true
  def matches_type?(%AshTypst.Document{}, _), do: true
  def matches_type?(_, _), do: false

  defp to_existing_atom(nil), do: nil
  defp to_existing_atom(atom) when is_atom(atom), do: atom
  defp to_existing_atom(string) when is_binary(string), do: String.to_existing_atom(string)
end
