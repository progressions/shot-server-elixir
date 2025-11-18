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
      shots: render_shots(fight)
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
        |> Enum.map(&render_encounter_character/1)
        |> Enum.sort_by(&character_sort_key/1)

      # Render vehicles for this shot
      vehicles =
        vehicle_shots
        |> Enum.map(&render_encounter_vehicle/1)

      %{
        shot: shot_number,
        characters: characters,
        vehicles: vehicles
      }
    end)
  end

  defp get_character_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      shots ->
        shots
        |> Enum.filter(& &1.character_id)
        |> Enum.map(& &1.character_id)
        |> Enum.uniq()
    end
  end

  defp get_vehicle_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      shots ->
        shots
        |> Enum.filter(& &1.vehicle_id)
        |> Enum.map(& &1.vehicle_id)
        |> Enum.uniq()
    end
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

  defp render_encounter_character(shot) do
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
          location: shot.location,
          driving_id: shot.driving_id,
          status: [],
          image_url: nil,
          faction: nil,
          weapon_ids: [],
          schtick_ids: [],
          effects: []
        }

      character ->
        # Ensure we have a valid character with action_values
        action_values = case character.action_values do
          nil -> %{}  # Fallback to empty map if nil
          values when is_map(values) -> values
          _ -> %{}
        end

        %{
          id: character.id,
          name: character.name,
          entity_class: "Character",
          action_values: action_values,
      skills: character.skills,
      faction_id: character.faction_id,
      color: character.color,
      count: shot.count,
      impairments: get_character_impairments(character, shot),
      shot_id: shot.id,
      current_shot: shot.shot,
      location: shot.location,
      driving_id: shot.driving_id,
      status: character.status,
      image_url: get_image_url(character),
      faction: render_faction_if_loaded(character),
          weapon_ids: get_weapon_ids(character),
          schtick_ids: get_schtick_ids(character),
          effects: [] # TODO: Implement character effects
        }
    end
  end

  defp render_encounter_vehicle(shot) do
    vehicle = shot.vehicle

    %{
      id: vehicle.id,
      name: vehicle.name,
      entity_class: "Vehicle",
      action_values: vehicle.action_values,
      shot_id: shot.id,
      current_shot: shot.shot,
      location: shot.location,
      driver_id: shot.driver_id,
      was_rammed_or_damaged: shot.was_rammed_or_damaged,
      image_url: get_image_url(vehicle),
      chase_relationships: [], # TODO: Implement chase relationships
      effects: [] # TODO: Implement vehicle effects
    }
  end

  defp character_sort_key(character) do
    # Sort order: Uber-Boss, Boss, PC, Ally, Featured Foe, Mook
    type = character.action_values["Type"] || "Mook"
    type_order = case type do
      "Uber-Boss" -> 1
      "Boss" -> 2
      "PC" -> 3
      "Ally" -> 4
      "Featured Foe" -> 5
      "Mook" -> 6
      _ -> 7
    end

    speed = (character.action_values["Speed"] || 0) - (character.impairments || 0)
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
end