defmodule ShotElixirWeb.Api.V2.SiteView do
  def render("index.json", %{sites: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{sites: sites, meta: meta, is_autocomplete: is_autocomplete} ->
        site_serializer =
          if is_autocomplete, do: &render_site_autocomplete/1, else: &render_site/1

        %{
          sites: Enum.map(sites, site_serializer),
          meta: meta
        }

      %{sites: sites, meta: meta} ->
        %{
          sites: Enum.map(sites, &render_site/1),
          meta: meta
        }

      sites when is_list(sites) ->
        # Legacy format for backward compatibility
        %{
          sites: Enum.map(sites, &render_site/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(sites),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{site: site}) do
    render_site(site)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_site(site) do
    %{
      id: site.id,
      name: site.name,
      description: site.description,
      active: site.active,
      faction_id: site.faction_id,
      campaign_id: site.campaign_id,
      juncture_id: site.juncture_id,
      character_ids: get_character_ids(site),
      created_at: site.created_at,
      updated_at: site.updated_at,
      image_url: site.image_url,
      characters: render_characters_if_loaded(site),
      faction: render_faction_if_loaded(site),
      image_positions: render_image_positions_if_loaded(site),
      entity_class: "Site"
    }
  end

  defp render_site_autocomplete(site) do
    %{
      id: site.id,
      name: site.name,
      entity_class: "Site"
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

  defp get_character_ids(site) do
    case Map.get(site, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, & &1.id)
    end
  end

  defp render_characters_if_loaded(site) do
    case Map.get(site, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, &render_character_lite/1)
    end
  end

  defp render_faction_if_loaded(site) do
    case Map.get(site, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_lite(faction)
    end
  end

  defp render_image_positions_if_loaded(site) do
    case Map.get(site, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      entity_class: "Character"
    }
  end

  defp render_faction_lite(faction) do
    %{
      id: faction.id,
      name: faction.name,
      entity_class: "Faction"
    }
  end

  defp render_image_position(position) do
    %{
      id: position.id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides
    }
  end
end