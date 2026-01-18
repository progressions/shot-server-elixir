defmodule ShotElixirWeb.Api.V2.SearchView do
  @moduledoc """
  View for rendering search results with full entity data.

  Delegates to existing view modules to avoid code duplication and ensure
  consistency with index view formats across the application.
  """

  alias ShotElixirWeb.Api.V2.{
    CharacterView,
    VehicleView,
    FightView,
    SiteView,
    PartyView,
    FactionView,
    SchticksView,
    WeaponView,
    JunctureView,
    AdventureView
  }

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
      {Atom.to_string(type), render_items_for_type(type, items)}
    end)
    |> Map.new()
  end

  # Delegate rendering to existing view modules
  defp render_items_for_type(:characters, items) do
    Enum.map(items, &CharacterView.render_for_index/1)
  end

  defp render_items_for_type(:vehicles, items) do
    Enum.map(items, &VehicleView.render_for_index/1)
  end

  defp render_items_for_type(:fights, items) do
    Enum.map(items, &FightView.render_for_index/1)
  end

  defp render_items_for_type(:sites, items) do
    Enum.map(items, &SiteView.render_for_index/1)
  end

  defp render_items_for_type(:parties, items) do
    Enum.map(items, &PartyView.render_for_index/1)
  end

  defp render_items_for_type(:factions, items) do
    Enum.map(items, &FactionView.render_for_index/1)
  end

  defp render_items_for_type(:schticks, items) do
    Enum.map(items, &SchticksView.render_for_index/1)
  end

  defp render_items_for_type(:weapons, items) do
    Enum.map(items, &WeaponView.render_for_index/1)
  end

  defp render_items_for_type(:junctures, items) do
    Enum.map(items, &JunctureView.render_for_index/1)
  end

  defp render_items_for_type(:adventures, items) do
    Enum.map(items, &AdventureView.render_for_index/1)
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
