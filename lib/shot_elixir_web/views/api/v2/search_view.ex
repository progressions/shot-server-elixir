defmodule ShotElixirWeb.Api.V2.SearchView do
  @moduledoc """
  View for rendering search results.
  """

  def render("index.json", %{results: results, meta: meta}) do
    %{
      results: render_results(results),
      meta: meta
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  # Render results map, converting atom keys to string keys for JSON
  defp render_results(results) do
    results
    |> Enum.map(fn {type, items} ->
      {Atom.to_string(type), Enum.map(items, &render_result_item/1)}
    end)
    |> Map.new()
  end

  defp render_result_item(item) do
    %{
      id: item.id,
      name: item.name,
      image_url: item.image_url,
      entity_class: item.entity_class,
      description: item.description
    }
  end

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(error), do: error
end
