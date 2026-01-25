defmodule ShotElixirWeb.Api.V2.EncounterView do
  def render("show.json", %{encounter: encounter}) do
    render_encounter(encounter)
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

  defp render_encounter(fight) do
    %{
      id: fight.id,
      entity_class: "Fight",
      name: fight.name,
      sequence: fight.sequence,
      description: fight.description,
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      image_url: get_image_url(fight),
      character_ids: get_character_ids(fight),
      vehicle_ids: get_vehicle_ids(fight),
      action_id: fight.action_id,
      shots: render_shots(fight),
      character_effects: get_character_effects_map(fight),
      vehicle_effects: get_vehicle_effects_map(fight),
      # Solo play fields
      solo_mode: fight.solo_mode,
      solo_player_character_ids: fight.solo_player_character_ids || [],
      solo_behavior_type: fight.solo_behavior_type
    }
  end

  defp render_shots(fight) do
    # Group shots by shot number and render characters/vehicles
    fight.shots
    |> Enum.group_by(& &1.shot)
    |> Enum.sort_by(&elem(&1, 0), &sort_shots_desc_nulls_last/2)
    |> Enum.map(fn {shot_number, shots} ->
      # Separate character and vehicle shots
      character_shots = Enum.filter(shots, & &1.character_id)
      vehicle_shots = Enum.filter(shots, & &1.vehicle_id)

      # Render characters for this shot
      characters =
        character_shots
        |> Enum.map(&render_encounter_character(&1, fight))
        |> Enum.sort_by(&character_sort_key/1)

      # Get all vehicle shot IDs that are being driven by characters
      driven_vehicle_shot_ids =
        fight.shots
        |> Enum.filter(& &1.character_id)
        |> Enum.map(& &1.driving_id)
        |> Enum.reject(&is_nil/1)
        |> MapSet.new()

      # Render vehicles for this shot (exclude vehicles being driven - they appear with the driver)
      vehicles =
        vehicle_shots
        |> Enum.filter(fn shot -> not MapSet.member?(driven_vehicle_shot_ids, shot.id) end)
        |> Enum.map(&render_encounter_vehicle(&1, fight))

      %{
        shot: shot_number,
        characters: characters,
        vehicles: vehicles
      }
    end)
  end

  defp get_character_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      shots ->
        shots
        |> Enum.filter(& &1.character_id)
        |> Enum.map(& &1.character_id)
    end
  end

  defp get_vehicle_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      shots ->
        shots
        |> Enum.filter(& &1.vehicle_id)
        |> Enum.map(& &1.vehicle_id)
    end
  end

  # Build a map of character_id => [effects] for the top-level encounter response
  defp get_character_effects_map(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} ->
        %{}

      nil ->
        %{}

      shots ->
        shots
        |> Enum.filter(& &1.character_id)
        |> Enum.reduce(%{}, fn shot, acc ->
          effects = render_effects(shot)

          if Enum.empty?(effects) do
            acc
          else
            # Use Map.update to concatenate effects from multiple shots
            Map.update(acc, shot.character_id, effects, fn existing -> existing ++ effects end)
          end
        end)
    end
  end

  # Build a map of vehicle_id => [effects] for the top-level encounter response
  defp get_vehicle_effects_map(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} ->
        %{}

      nil ->
        %{}

      shots ->
        shots
        |> Enum.filter(& &1.vehicle_id)
        |> Enum.reduce(%{}, fn shot, acc ->
          effects = render_effects(shot)

          if Enum.empty?(effects) do
            acc
          else
            # Use Map.update to concatenate effects from multiple shots
            Map.update(acc, shot.vehicle_id, effects, fn existing -> existing ++ effects end)
          end
        end)
    end
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

  defp render_encounter_character(shot, fight) do
    character = shot.character

    # Handle case where character association might not be loaded
    case character do
      nil ->
        # Character not loaded, return placeholder
        %{
          id: nil,
          name: "Character not loaded",
          entity_class: "Character",
          action_values: %{},
          skills: %{},
          faction_id: nil,
          color: nil,
          count: shot.count,
          impairments: 0,
          shot_id: shot.id,
          current_shot: shot.shot,
          location: get_location_name(shot),
          driving_id: shot.driving_id,
          driving: nil,
          status: [],
          image_url: nil,
          faction: nil,
          weapon_ids: [],
          schtick_ids: [],
          effects: [],
          user_id: nil
        }

      character ->
        # Ensure we have a valid character with action_values
        action_values =
          case character.action_values do
            # Fallback to empty map if nil
            nil -> %{}
            values when is_map(values) -> values
            _ -> %{}
          end

        # Find the driving vehicle if character has a driving_id
        driving_vehicle = get_driving_vehicle(shot.driving_id, fight)

        %{
          id: character.id,
          name: character.name,
          entity_class: "Character",
          action_values: action_values,
          skills: character.skills,
          faction_id: character.faction_id,
          color: shot.color || character.color,
          count: shot.count,
          impairments: get_character_impairments(character, shot),
          shot_id: shot.id,
          current_shot: shot.shot,
          location: get_location_name(shot),
          driving_id: shot.driving_id,
          driving: driving_vehicle,
          status: character.status,
          image_url: get_image_url(character),
          faction: render_faction_if_loaded(character),
          weapon_ids: get_weapon_ids(character),
          equipped_weapon_id: character.equipped_weapon_id,
          schtick_ids: get_schtick_ids(character),
          effects: render_effects(shot),
          user_id: character.user_id,
          user: render_user_if_loaded(character)
        }
    end
  end

  defp render_user_if_loaded(character) do
    case Map.get(character, :user) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      user -> %{id: user.id, name: "#{user.first_name} #{user.last_name}", email: user.email}
    end
  end

  # Find the vehicle that the character is driving based on driving_id (which is a shot_id)
  defp get_driving_vehicle(nil, _fight), do: nil

  defp get_driving_vehicle(driving_id, fight) do
    # driving_id is the shot_id of the vehicle shot
    vehicle_shot =
      fight.shots
      |> Enum.find(fn s -> s.id == driving_id && s.vehicle_id end)

    case vehicle_shot do
      nil ->
        nil

      shot ->
        vehicle = shot.vehicle

        # Handle case where vehicle association might not be loaded
        case vehicle do
          %Ecto.Association.NotLoaded{} -> nil
          nil -> nil
          vehicle -> build_vehicle_map(vehicle, shot, fight)
        end
    end
  end

  defp render_encounter_vehicle(shot, fight) do
    case shot.vehicle do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      vehicle -> build_vehicle_map(vehicle, shot, fight)
    end
  end

  defp get_vehicle_driver(shot, fight) do
    case shot.driver_id do
      nil ->
        nil

      driver_shot_id ->
        driver_shot =
          fight.shots
          |> Enum.find(fn s -> s.id == driver_shot_id && s.character_id end)

        case driver_shot && driver_shot.character do
          %Ecto.Association.NotLoaded{} ->
            nil

          nil ->
            nil

          character ->
            %{
              id: character.id,
              name: character.name,
              entity_class: "Character",
              shot_id: driver_shot.id
            }
        end
    end
  end

  # Shared helper to build vehicle map structure
  defp build_vehicle_map(vehicle, shot, fight) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      entity_class: "Vehicle",
      action_values: vehicle.action_values,
      shot_id: shot.id,
      current_shot: shot.shot,
      location: get_location_name(shot),
      driver_id: shot.driver_id,
      driver: get_vehicle_driver(shot, fight),
      was_rammed_or_damaged: shot.was_rammed_or_damaged,
      image_url: get_image_url(vehicle),
      chase_relationships: get_chase_relationships_for_vehicle(fight, vehicle.id),
      effects: render_effects(shot)
    }
  end

  defp render_effects(shot) do
    case Map.get(shot, :character_effects) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      effects ->
        Enum.map(effects, fn effect ->
          %{
            id: effect.id,
            name: effect.name,
            description: effect.description,
            severity: effect.severity,
            action_value: effect.action_value,
            change: effect.change,
            shot_id: effect.shot_id,
            character_id: effect.character_id,
            vehicle_id: effect.vehicle_id
          }
        end)
    end
  end

  defp character_sort_key(character) do
    # Sort order: Uber-Boss, Boss, PC, Ally, Featured Foe, Mook
    type = character.action_values["Type"] || "Mook"

    type_order =
      case type do
        "Uber-Boss" -> 1
        "Boss" -> 2
        "PC" -> 3
        "Ally" -> 4
        "Featured Foe" -> 5
        "Mook" -> 6
        _ -> 7
      end

    speed = to_integer(character.action_values["Speed"]) - (character.impairments || 0)
    name = String.downcase(character.name || "")

    {type_order, -speed, name}
  end

  defp get_character_impairments(character, shot) do
    # For PCs, use character.impairments, for others use shot.impairments
    if character.action_values["Type"] == "PC" do
      character.impairments || 0
    else
      shot.impairments || 0
    end
  end

  defp render_faction_if_loaded(character) do
    case Map.get(character, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> %{id: faction.id, name: faction.name}
    end
  end

  defp get_weapon_ids(character) do
    case Map.get(character, :carries) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      carries -> Enum.map(carries, & &1.weapon_id)
    end
  end

  defp get_schtick_ids(character) do
    case Map.get(character, :character_schticks) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      character_schticks -> Enum.map(character_schticks, & &1.schtick_id)
    end
  end

  # Custom sorting function to sort shots DESC NULLS LAST (like Rails "shots.shot DESC NULLS LAST")
  # This ensures Hidden shots (with nil shot values) appear last instead of first
  defp sort_shots_desc_nulls_last(nil, nil), do: true
  defp sort_shots_desc_nulls_last(nil, _), do: false
  defp sort_shots_desc_nulls_last(_, nil), do: true
  defp sort_shots_desc_nulls_last(a, b), do: a >= b

  defp get_chase_relationships_for_vehicle(fight, vehicle_id) do
    # Filter preloaded chase relationships for this fight and vehicle
    # Matches Rails: chase_relationships.select { |cr| cr.pursuer_id == vehicle_id || cr.evader_id == vehicle_id }
    case Map.get(fight, :chase_relationships) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      chase_relationships ->
        chase_relationships
        |> Enum.filter(fn cr ->
          cr.active && (cr.pursuer_id == vehicle_id || cr.evader_id == vehicle_id)
        end)
        |> Enum.map(fn cr ->
          %{
            id: cr.id,
            position: cr.position,
            pursuer_id: cr.pursuer_id,
            evader_id: cr.evader_id,
            is_pursuer: cr.pursuer_id == vehicle_id
          }
        end)
    end
  end

  # Helper to safely convert action values to integers
  # Some values may be stored as strings (e.g., "8" instead of 8)
  defp to_integer(nil), do: 0
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(_), do: 0

  # Get the location name from the shot's location_ref association
  # Falls back to the legacy location string field for backwards compatibility
  defp get_location_name(shot) do
    case Map.get(shot, :location_ref) do
      %Ecto.Association.NotLoaded{} -> shot.location
      nil -> shot.location
      location -> location.name
    end
  end
end
