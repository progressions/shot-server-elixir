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
          maybe_create_event(fight, update)
          apply_shot_updates(shot, update)
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
    Fights.create_fight_event(%{
      "fight_id" => fight.id,
      "event_type" => event_data["event_type"] || event_data["type"] || "combat_action",
      "description" => event_data["description"] || "Combat action",
      "details" => event_data["details"] || event_data
    })
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
  defp build_shot_updates(_shot, update) do
    %{}
    |> maybe_add("shot", update["shot"])
    |> maybe_add("impairments", update["impairments"])
    |> maybe_add("count", update["count"])
  end

  # Build map of character-level updates (for PCs/named NPCs)
  defp build_character_updates(shot, update) do
    character = shot.character || %{}

    # Only update character wounds if this is a PC or named NPC
    # Mooks use count on the shot instead
    if update["wounds"] && !is_mook?(character) do
      current_wounds = get_current_wounds(character)
      new_wounds = current_wounds + update["wounds"]

      %{"action_values" => %{"Wounds" => new_wounds}}
    else
      %{}
    end
  end

  # Helper to check if character is a mook
  defp is_mook?(%Character{action_values: action_values}) when is_map(action_values) do
    action_values["Type"] == "Mook"
  end

  defp is_mook?(_), do: false

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
