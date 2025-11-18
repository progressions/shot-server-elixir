defmodule ShotElixirWeb.Api.V2.FactionView do
  def render("index.json", %{factions: factions, meta: meta}) do
    %{
      factions: Enum.map(factions, &render_faction/1),
      meta: meta
    }
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
      active: faction.active,
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
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
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
        entity_type = case Map.get(record, :__struct__) do
          nil -> nil  # Plain map, skip ActiveStorage lookup
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