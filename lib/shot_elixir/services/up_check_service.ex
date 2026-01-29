defmodule ShotElixir.Services.UpCheckService do
  @moduledoc """
  Handles Up Check actions (recovery rolls).
  """

  require Logger
  alias ShotElixir.{Repo, Fights, Characters}
  alias ShotElixir.Fights.Fight
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
  # A successful up check only clears the up_check_required status.
  # It does NOT reduce wounds - the character stays up but keeps their wounds.
  defp handle_up_check_success(_fight, character, _char_type, current_status) do
    new_status = Enum.reject(current_status, &(&1 == "up_check_required"))
    update_character_status(character, new_status, "up check passed")
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
