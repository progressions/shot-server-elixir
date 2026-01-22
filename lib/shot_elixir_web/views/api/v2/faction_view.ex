defmodule ShotElixirWeb.Api.V2.FactionView do
  def render("index.json", %{factions: factions, meta: meta}) do
    %{
      factions: Enum.map(factions, &render_faction/1),
      meta: meta
    }
  end

  def render("show.json", %{faction: faction, is_gm: is_gm}) do
    render_faction(faction, is_gm)
  end

  def render("show.json", %{faction: faction}) do
    # Default to false for backwards compatibility - non-GM users don't see GM-only content
    render_faction(faction, false)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  @doc """
  Render a faction for search results or index listings.
  Public function for use by SearchView and other views.
  """
  def render_for_index(faction), do: render_faction(faction, false)

  defp render_faction(faction, is_gm \\ false) do
    base = %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      active: faction.active,
      at_a_glance: faction.at_a_glance,
      campaign_id: faction.campaign_id,
      created_at: faction.created_at,
      updated_at: faction.updated_at,
      image_url: get_image_url(faction),
      character_ids: get_character_ids(faction),
      characters: render_characters_if_loaded(faction),
      vehicle_ids: get_vehicle_ids(faction),
      vehicles: render_vehicles_if_loaded(faction),
      site_ids: get_site_ids(faction),
      sites: render_sites_if_loaded(faction),
      party_ids: get_party_ids(faction),
      parties: render_parties_if_loaded(faction),
      juncture_ids: get_juncture_ids(faction),
      junctures: render_junctures_if_loaded(faction),
      image_positions: render_image_positions_if_loaded(faction),
      notion_page_id: faction.notion_page_id,
      last_synced_to_notion_at: faction.last_synced_to_notion_at,
      rich_description: faction.rich_description,
      mentions: faction.mentions,
      entity_class: "Faction"
    }

    # Only include GM-only content for gamemasters
    if is_gm do
      Map.put(base, :rich_description_gm_only, faction.rich_description_gm_only)
    else
      base
    end
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

  defp get_character_ids(faction) do
    case Map.get(faction, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, & &1.id)
    end
  end

  defp get_vehicle_ids(faction) do
    case Map.get(faction, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, & &1.id)
    end
  end

  defp get_site_ids(faction) do
    case Map.get(faction, :sites) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      sites -> Enum.map(sites, & &1.id)
    end
  end

  defp get_party_ids(faction) do
    case Map.get(faction, :parties) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      parties -> Enum.map(parties, & &1.id)
    end
  end

  defp get_juncture_ids(faction) do
    case Map.get(faction, :junctures) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      junctures -> Enum.map(junctures, & &1.id)
    end
  end

  defp render_characters_if_loaded(faction) do
    case Map.get(faction, :characters) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      characters ->
        # Load image URLs for all characters efficiently
        characters_with_images = ShotElixir.ImageLoader.load_image_urls(characters, "Character")
        Enum.map(characters_with_images, &render_character_lite/1)
    end
  end

  defp render_vehicles_if_loaded(faction) do
    case Map.get(faction, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, &render_vehicle_lite/1)
    end
  end

  defp render_sites_if_loaded(faction) do
    case Map.get(faction, :sites) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      sites -> Enum.map(sites, &render_site_lite/1)
    end
  end

  defp render_parties_if_loaded(faction) do
    case Map.get(faction, :parties) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      parties -> Enum.map(parties, &render_party_lite/1)
    end
  end

  defp render_junctures_if_loaded(faction) do
    case Map.get(faction, :junctures) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      junctures -> Enum.map(junctures, &render_juncture_lite/1)
    end
  end

  defp render_image_positions_if_loaded(faction) do
    case Map.get(faction, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  defp render_vehicle_lite(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      entity_class: "Vehicle"
    }
  end

  defp render_site_lite(site) do
    %{
      id: site.id,
      name: site.name,
      entity_class: "Site"
    }
  end

  defp render_party_lite(party) do
    %{
      id: party.id,
      name: party.name,
      entity_class: "Party"
    }
  end

  defp render_juncture_lite(juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      entity_class: "Juncture"
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

  # Rails-compatible image URL handling
  defp get_image_url(record) when is_map(record) do
    # Check if image_url is already in the record (pre-loaded)
    case Map.get(record, :image_url) do
      nil ->
        # Try to get entity type from struct, fallback to nil if plain map
        entity_type =
          case Map.get(record, :__struct__) do
            # Plain map, skip ActiveStorage lookup
            nil -> nil
            struct_module -> struct_module |> Module.split() |> List.last()
          end

        if entity_type && Map.get(record, :id) do
          ShotElixir.ActiveStorage.get_image_url(entity_type, record.id)
        else
          nil
        end

      url ->
        url
    end
  end

  defp get_image_url(_), do: nil
end
