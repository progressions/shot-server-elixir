defmodule ShotElixirWeb.Api.V2.FactionView do
  def render("index.json", %{factions: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{factions: factions, meta: meta, is_autocomplete: is_autocomplete} ->
        faction_serializer =
          if is_autocomplete, do: &render_faction_autocomplete/1, else: &render_faction/1

        %{
          factions: Enum.map(factions, faction_serializer),
          meta: meta
        }

      %{factions: factions, meta: meta} ->
        %{
          factions: Enum.map(factions, &render_faction/1),
          meta: meta
        }

      factions when is_list(factions) ->
        # Legacy format for backward compatibility
        %{
          factions: Enum.map(factions, &render_faction/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(factions),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{faction: faction}) do
    render_faction(faction)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_faction(faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      campaign_id: faction.campaign_id,
      created_at: faction.created_at,
      updated_at: faction.updated_at,
      image_url: faction.image_url,
      entity_class: "Faction"
    }
  end

  defp render_faction_autocomplete(faction) do
    %{
      id: faction.id,
      name: faction.name,
      entity_class: "Faction"
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

  defp translate_errors(errors), do: errors
end