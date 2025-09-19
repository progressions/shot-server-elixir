defmodule ShotElixirWeb.Api.V2.FightView do
  def render("index.json", %{fights: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{fights: fights, seasons: seasons, meta: meta, is_autocomplete: is_autocomplete} ->
        fight_serializer =
          if is_autocomplete, do: &render_fight_autocomplete/1, else: &render_fight/1

        %{
          fights: Enum.map(fights, fight_serializer),
          seasons: seasons,
          meta: meta
        }

      %{fights: fights, seasons: seasons, meta: meta} ->
        %{
          fights: Enum.map(fights, &render_fight/1),
          seasons: seasons,
          meta: meta
        }

      fights when is_list(fights) ->
        # Legacy format for backward compatibility
        %{
          fights: Enum.map(fights, &render_fight/1),
          seasons: [],
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
    render_fight_detail(fight)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  # Rails FightSerializer format
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
      character_ids: get_association_ids(fight, :characters),
      vehicles: render_vehicles_if_loaded(fight),
      vehicle_ids: get_association_ids(fight, :vehicles),
      entity_class: "Fight",
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      season: fight.season,
      session: fight.session,
      campaign_id: fight.campaign_id,
      image_positions: render_image_positions_if_loaded(fight)
    }
  end

  defp render_fight_autocomplete(fight) do
    %{
      id: fight.id,
      name: fight.name,
      entity_class: "Fight"
    }
  end

  defp render_fight_detail(fight) do
    base = render_fight(fight)

    # Add associations if they're loaded
    shots =
      case Map.get(fight, :shots) do
        %Ecto.Association.NotLoaded{} -> []
        shots -> Enum.map(shots, &render_shot/1)
      end

    Map.merge(base, %{
      shots: shots
    })
  end

  defp render_shot(shot) do
    %{
      id: shot.id,
      shot: shot.shot,
      character_id: shot.character_id,
      vehicle_id: shot.vehicle_id,
      acted: shot.acted,
      sequence: shot.sequence
    }
  end

  # Helper functions for Rails-compatible associations
  defp render_characters_if_loaded(fight) do
    case Map.get(fight, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, &render_character_autocomplete/1)
    end
  end

  defp render_vehicles_if_loaded(fight) do
    case Map.get(fight, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, &render_vehicle_lite/1)
    end
  end

  defp render_image_positions_if_loaded(fight) do
    case Map.get(fight, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp get_association_ids(record, association) do
    case Map.get(record, association) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      items when is_list(items) -> Enum.map(items, & &1.id)
      _ -> []
    end
  end

  # Rails CharacterAutocompleteSerializer format
  defp render_character_autocomplete(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  # Rails VehicleLiteSerializer format
  defp render_vehicle_lite(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      entity_class: "Vehicle"
    }
  end

  # Rails ImagePositionSerializer format
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
  defp get_image_url(record) do
    # TODO: Implement proper image attachment checking
    # For now, return nil like Rails when no image is attached
    Map.get(record, :image_url)
  end
end
