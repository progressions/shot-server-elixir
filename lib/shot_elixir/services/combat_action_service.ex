defmodule ShotElixir.Services.CombatActionService do
  @moduledoc """
  Handles batched combat actions including attacks, damage, and shot spending.
  Processes multiple character updates in a single transaction for combat scenarios.
  """

  require Logger
  alias ShotElixir.{Repo, Fights, Characters}
  alias ShotElixir.Fights.Fight
  alias ShotElixir.Characters.Character

  @doc """
  Applies a batched combat action with multiple character updates.

  ## Parameters
  - fight: The Fight struct
  - character_updates: List of character update maps containing:
    - shot_id: ID of the shot to update
    - character_id: ID of the character being updated
    - shot: New shot value (optional)
    - wounds: Wounds to add (optional)
    - impairments: New impairment count (optional)
    - count: New mook count (optional)
    - add_status: List of status strings to add (optional)
    - remove_status: List of status strings to remove (optional)
    - event: Combat event details (optional)

  ## Returns
  - {:ok, fight} on success
  - {:error, reason} on failure
  """
  def apply_combat_action(%Fight{} = fight, character_updates) when is_list(character_updates) do
    Logger.info("🔄 Processing #{length(character_updates)} combat updates for fight #{fight.id}")

    Repo.transaction(fn ->
      Enum.each(character_updates, fn update ->
        case process_character_update(fight, update) do
          {:ok, _result} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to process character update: #{inspect(reason)}")
            Repo.rollback(reason)
        end
      end)

      # Touch the fight to update timestamp
      Fights.touch_fight(fight)

      fight
    end)
  end

  # Process a single character update
  defp process_character_update(fight, %{"shot_id" => shot_id} = update) do
    case Fights.get_shot(shot_id) do
      nil ->
        {:error, "Shot #{shot_id} not found"}

      shot ->
        if shot.fight_id == fight.id do
          # Preload character to check type for wounds routing
          shot = Repo.preload(shot, :character)

          with :ok <- maybe_create_event(fight, update) do
            apply_shot_updates(shot, update)
          end
        else
          {:error, "Shot #{shot_id} does not belong to fight #{fight.id}"}
        end
    end
  end

  defp process_character_update(_fight, update) do
    Logger.warning("Character update missing shot_id: #{inspect(update)}")
    {:ok, :skipped}
  end

  defp maybe_create_event(fight, %{"event" => event_data}) when is_map(event_data) do
    case Fights.create_fight_event(%{
           "fight_id" => fight.id,
           "event_type" => event_data["event_type"] || event_data["type"] || "combat_action",
           "description" => event_data["description"] || "Combat action",
           "details" => event_data["details"] || event_data
         }) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to create fight event: #{inspect(changeset)}")
        {:error, "Failed to create fight event: #{inspect(changeset)}"}
    end
  end

  defp maybe_create_event(_fight, _update), do: :ok

  # Apply all updates to a shot
  defp apply_shot_updates(shot, update) do
    updates = build_shot_updates(shot, update)
    character_updates = build_character_updates(shot, update)

    # Update shot if there are shot-level changes
    result =
      if map_size(updates) > 0 do
        case Fights.update_shot(shot, updates) do
          {:ok, updated_shot} ->
            log_shot_update(updated_shot, updates)
            {:ok, updated_shot}

          error ->
            error
        end
      else
        {:ok, shot}
      end

    # Update character if there are character-level changes (e.g., wounds for PCs)
    if map_size(character_updates) > 0 && shot.character_id do
      case Characters.get_character(shot.character_id) do
        nil ->
          result

        character ->
          case Characters.update_character(character, character_updates) do
            {:ok, updated_character} ->
              log_character_update(updated_character, character_updates)
              {:ok, updated_character}

            error ->
              error
          end
      end
    else
      result
    end
  end

  # Build map of shot-level updates
  defp build_shot_updates(shot, update) do
    base_updates =
      %{}
      |> maybe_add("shot", update["shot"])
      |> maybe_add("impairments", update["impairments"])
      |> maybe_add("count", update["count"])

    # For NPCs (non-PCs), wounds go to shots.count, not character.action_values
    character = shot.character || %{}

    if update["wounds"] && !is_pc?(character) do
      current_count = shot.count || 0
      new_count = current_count + update["wounds"]
      Map.put(base_updates, "count", new_count)
    else
      base_updates
    end
  end

  # Build map of character-level updates
  defp build_character_updates(shot, update) do
    character = shot.character || %{}

    base_updates =
      cond do
        # If action_values is sent directly, pass it through (for PCs)
        update["action_values"] && is_pc?(character) ->
          %{"action_values" => update["action_values"]}

        # If wounds is sent separately, build the action_values (for PCs)
        update["wounds"] && is_pc?(character) ->
          current_wounds = get_current_wounds(character)
          new_wounds = current_wounds + update["wounds"]
          %{"action_values" => %{"Wounds" => new_wounds}}

        true ->
          %{}
      end

    # Handle status additions and removals
    base_updates
    |> maybe_add_status_updates(character, update)
    |> maybe_add_up_check_status(character, update, shot)
  end

  # Check if wounds crossed the up_check threshold and add up_check_required status
  defp maybe_add_up_check_status(updates, character, update, shot) do
    char_type = get_character_type(character)
    threshold = get_wound_threshold(char_type)

    # Skip if no threshold for this character type
    if threshold == nil do
      updates
    else
      # For Boss/Uber-Boss, wounds are stored in shot.count, not character.action_values
      old_wounds =
        case char_type do
          t when t in ["Boss", "Uber-Boss"] -> shot.count || 0
          _ -> get_current_wounds(character)
        end

      # Calculate new wounds after this update
      new_wounds =
        cond do
          # PC with direct action_values["Wounds"] update
          is_pc?(character) && update["action_values"] &&
              Map.has_key?(update["action_values"], "Wounds") ->
            update["action_values"]["Wounds"]

          # PC with incremental wounds update
          is_pc?(character) && update["wounds"] ->
            old_wounds + update["wounds"]

          # Boss/Uber-Boss with direct count update
          char_type in ["Boss", "Uber-Boss"] && update["count"] != nil ->
            update["count"]

          # Boss/Uber-Boss with incremental wounds update
          char_type in ["Boss", "Uber-Boss"] && update["wounds"] ->
            old_wounds + update["wounds"]

          true ->
            old_wounds
        end

      current_status = get_current_status(character)
      has_up_check = "up_check_required" in current_status

      # Enforce up_check_required status based on wound threshold
      cond do
        # At or above threshold - ensure up_check_required is present (for PC, Boss, Uber-Boss)
        new_wounds >= threshold && !has_up_check && char_type in ["PC", "Boss", "Uber-Boss"] ->
          Logger.info(
            "⚠️ #{character.name} is at or above wound threshold (#{old_wounds} -> #{new_wounds}), enforcing Up Check"
          )

          new_status = Enum.uniq((updates["status"] || current_status) ++ ["up_check_required"])
          Map.put(updates, "status", new_status)

        # Healed below threshold - remove up_check_required
        new_wounds < threshold && has_up_check ->
          new_status =
            Enum.reject(updates["status"] || current_status, &(&1 == "up_check_required"))

          Map.put(updates, "status", new_status)

        true ->
          updates
      end
    end
  end

  # Get wound threshold based on character type
  defp get_wound_threshold("Uber-Boss"), do: 50
  defp get_wound_threshold("Boss"), do: 50
  defp get_wound_threshold("PC"), do: 35
  # Allies and Featured Foes go straight to out_of_fight, no Up Check
  defp get_wound_threshold(_), do: nil

  # Get character type from action_values
  defp get_character_type(%Character{action_values: action_values}) when is_map(action_values) do
    action_values["Type"]
  end

  defp get_character_type(_), do: nil

  # Handle add_status and remove_status updates
  defp maybe_add_status_updates(updates, character, update) do
    current_status = get_current_status(character)

    # Add new statuses
    status_after_add =
      case update["add_status"] do
        statuses when is_list(statuses) and length(statuses) > 0 ->
          Enum.uniq(current_status ++ statuses)

        _ ->
          current_status
      end

    # Remove statuses
    final_status =
      case update["remove_status"] do
        statuses when is_list(statuses) and length(statuses) > 0 ->
          Enum.reject(status_after_add, &(&1 in statuses))

        _ ->
          status_after_add
      end

    # Only add status update if it changed
    if final_status != current_status do
      Map.put(updates, "status", final_status)
    else
      updates
    end
  end

  # Helper to get current status from character
  defp get_current_status(%Character{status: status}) when is_list(status), do: status
  defp get_current_status(_), do: []

  # Helper to check if character is a PC
  defp is_pc?(%Character{action_values: action_values}) when is_map(action_values) do
    action_values["Type"] == "PC"
  end

  defp is_pc?(_), do: false

  # Helper to get current wounds from character
  defp get_current_wounds(%Character{action_values: action_values}) when is_map(action_values) do
    action_values["Wounds"] || 0
  end

  defp get_current_wounds(_), do: 0

  # Add field to map if value is present
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  # Logging helpers
  defp log_shot_update(shot, updates) do
    shot_with_entity = Repo.preload(shot, [:character, :vehicle])
    entity_name = get_entity_name(shot_with_entity)

    Enum.each(updates, fn {key, value} ->
      Logger.info("  Updated #{entity_name}: #{key} = #{value}")
    end)
  end

  defp log_character_update(character, updates) do
    Enum.each(updates, fn {key, value} ->
      Logger.info("  Updated #{character.name}: #{key} = #{inspect(value)}")
    end)
  end

  defp get_entity_name(shot) do
    cond do
      shot.character -> shot.character.name
      shot.vehicle -> shot.vehicle.name
      true -> "Unknown"
    end
  end
end
