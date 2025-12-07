defmodule ShotElixir.Services.UpCheckService do
  @moduledoc """
  Handles Up Check actions (recovery rolls).
  """

  require Logger
  import Ecto.Query
  alias ShotElixir.{Repo, Fights, Characters}
  alias ShotElixir.Fights.{Fight, Shot}
  alias ShotElixir.Characters.Character

  def apply_up_check(%Fight{} = fight, params) do
    Logger.info("Applying up check for fight #{fight.id}")

    Repo.transaction(fn ->
      # Record the event
      case Fights.create_fight_event(
             %{
               "fight_id" => fight.id,
               "event_type" => "up_check",
               "description" => "Up check performed",
               "details" => Map.take(params, ["character_id", "result", "success"])
             },
             broadcast: false
           ) do
        {:ok, _event} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      # Apply logic based on success/failure
      character_id = params["character_id"]
      character = Characters.get_character(character_id)

      if character do
        current_status = character.status || []
        char_type = get_character_type(character)

        if params["success"] do
          handle_up_check_success(fight, character, char_type, current_status)
        else
          handle_up_check_failure(character, current_status)
        end
      end

      fight
    end)
    |> case do
      {:ok, fight} -> Fights.touch_fight(fight)
      error -> error
    end
  end

  # Handle successful up check
  defp handle_up_check_success(fight, character, char_type, current_status)
       when char_type in ["Boss", "Uber-Boss"] do
    # For Boss/Uber-Boss, wounds are stored in shot.count
    new_status = Enum.reject(current_status, &(&1 == "up_check_required"))

    # Find the shot for this character in this fight
    case find_shot_for_character(fight, character) do
      nil ->
        # No shot found, just update character status
        update_character_status(character, new_status, "no shot found")

      shot ->
        wounds = shot.count || 0

        if wounds > 0 do
          # Reduce wounds on the shot
          case Fights.update_shot(shot, %{"count" => wounds - 1}) do
            {:ok, _} ->
              update_character_status(character, new_status, "wound reduced from shot.count")

            {:error, reason} ->
              Repo.rollback(reason)
          end
        else
          update_character_status(character, new_status, "no wounds to reduce")
        end
    end
  end

  defp handle_up_check_success(_fight, character, _char_type, current_status) do
    # For PCs and other types, wounds are in character.action_values
    action_values = character.action_values || %{}
    wounds = Map.get(action_values, "Wounds", 0)
    impairments = character.impairments || 0

    new_status = Enum.reject(current_status, &(&1 == "up_check_required"))

    updates =
      cond do
        wounds > 0 ->
          %{
            "action_values" => Map.put(action_values, "Wounds", wounds - 1),
            "status" => new_status
          }

        impairments > 0 ->
          %{"impairments" => impairments - 1, "status" => new_status}

        true ->
          # Even if no wounds/impairments to reduce, still clear the status
          %{"status" => new_status}
      end

    case Characters.update_character(character, updates) do
      {:ok, _} ->
        Logger.info("✅ UP CHECK SUCCESS: #{character.name} stays in the fight")
        :ok

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # Handle failed up check
  defp handle_up_check_failure(character, current_status) do
    new_status =
      current_status
      |> Enum.reject(&(&1 == "up_check_required"))
      |> Enum.concat(["out_of_fight"])
      |> Enum.uniq()

    case Characters.update_character(character, %{"status" => new_status}) do
      {:ok, _} ->
        Logger.info("❌ UP CHECK FAILED: #{character.name} is out of the fight")
        :ok

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # Find the shot for a character in a fight
  defp find_shot_for_character(fight, character) do
    Repo.one(
      from s in Shot,
        where: s.fight_id == ^fight.id and s.character_id == ^character.id,
        limit: 1
    )
  end

  # Update character status with logging
  defp update_character_status(character, new_status, reason) do
    case Characters.update_character(character, %{"status" => new_status}) do
      {:ok, _} ->
        Logger.info("✅ UP CHECK SUCCESS: #{character.name} stays in the fight (#{reason})")
        :ok

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # Get character type from action_values
  defp get_character_type(%Character{action_values: action_values}) when is_map(action_values) do
    action_values["Type"]
  end

  defp get_character_type(_), do: nil
end
