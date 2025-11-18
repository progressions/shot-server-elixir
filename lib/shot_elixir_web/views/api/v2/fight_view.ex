defmodule ShotElixirWeb.Api.V2.FightView do
  def render("index.json", %{fights: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{fights: fights, meta: meta, is_autocomplete: is_autocomplete} ->
        fight_serializer =
          if is_autocomplete, do: &render_fight_autocomplete/1, else: &render_fight/1

        %{
          fights: Enum.map(fights, fight_serializer),
          meta: meta
        }

      %{fights: fights, meta: meta} ->
        %{
          fights: Enum.map(fights, &render_fight/1),
          meta: meta
        }

      fights when is_list(fights) ->
        # Legacy format for backward compatibility
        %{
          fights: Enum.map(fights, &render_fight/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(fights),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{fight: fight}) do
    render_fight_detailed(fight)
  end

  def render("error.json", %{errors: errors}) do
    %{
      success: false,
      errors: translate_errors(errors)
    }
  end

  def render("error.json", %{error: error}) do
    %{
      success: false,
      errors: %{base: [error]}
    }
  end

  defp render_fight(fight) do
    %{
      id: fight.id,
      name: fight.name,
      description: fight.description,
      image_url: get_image_url(fight),
      created_at: fight.created_at,
      updated_at: fight.updated_at,
      active: fight.active,
      sequence: fight.sequence,
      characters: render_characters_if_loaded(fight),
      character_ids: get_character_ids(fight),
      vehicles: render_vehicles_if_loaded(fight),
      vehicle_ids: get_vehicle_ids(fight),
      entity_class: "Fight",
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      season: fight.season,
      session: fight.session,
      campaign_id: fight.campaign_id
    }
  end

  defp render_fight_detailed(fight) do
    base = render_fight(fight)

    # Add image positions if loaded
    image_positions =
      case Map.get(fight, :image_positions) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        positions -> Enum.map(positions, &render_image_position/1)
      end

    Map.merge(base, %{
      image_positions: image_positions
    })
  end

  defp render_characters_if_loaded(fight) do
    case Map.get(fight, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters ->
        # Load image URLs for all characters efficiently
        characters_with_images = ShotElixir.ImageLoader.load_image_urls(characters, "Character")
        Enum.map(characters_with_images, &render_character_autocomplete/1)
    end
  end

  defp render_vehicles_if_loaded(fight) do
    case Map.get(fight, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, &render_vehicle_lite/1)
    end
  end

  defp get_character_ids(fight) do
    case Map.get(fight, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, & &1.id)
    end
  end

  defp get_vehicle_ids(fight) do
    case Map.get(fight, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, & &1.id)
    end
  end

  defp render_character_autocomplete(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: character.image_url,
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

  defp render_fight_autocomplete(fight) do
    %{
      id: fight.id,
      name: fight.name,
      entity_class: "Fight"
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

  defp get_image_url(fight) do
    # TODO: Implement proper image attachment checking
    Map.get(fight, :image_url)
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