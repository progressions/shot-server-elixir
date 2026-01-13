defmodule ShotElixirWeb.Api.V2.JunctureView do
  def render("index.json", %{junctures: junctures, meta: meta}) do
    %{
      junctures: Enum.map(junctures, &render_juncture/1),
      meta: meta
    }
  end

  def render("show.json", %{juncture: juncture}) do
    render_juncture(juncture)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_juncture(juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description,
      active: juncture.active,
      at_a_glance: juncture.at_a_glance,
      faction_id: juncture.faction_id,
      campaign_id: juncture.campaign_id,
      character_ids: get_character_ids(juncture),
      vehicle_ids: get_vehicle_ids(juncture),
      created_at: juncture.created_at,
      updated_at: juncture.updated_at,
      image_url: get_image_url(juncture),
      characters: render_characters_if_loaded(juncture),
      vehicles: render_vehicles_if_loaded(juncture),
      faction: render_faction_if_loaded(juncture),
      image_positions: render_image_positions_if_loaded(juncture),
      entity_class: "Juncture"
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

  defp get_character_ids(juncture) do
    case Map.get(juncture, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, & &1.id)
    end
  end

  defp get_vehicle_ids(juncture) do
    case Map.get(juncture, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, & &1.id)
    end
  end

  defp render_characters_if_loaded(juncture) do
    case Map.get(juncture, :characters) do
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

  defp render_vehicles_if_loaded(juncture) do
    case Map.get(juncture, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, &render_vehicle_lite/1)
    end
  end

  defp render_faction_if_loaded(juncture) do
    case Map.get(juncture, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_lite(faction)
    end
  end

  defp render_image_positions_if_loaded(juncture) do
    case Map.get(juncture, :image_positions) do
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
