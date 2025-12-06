defmodule ShotElixir.Services.UpCheckService do
  @moduledoc """
  Handles Up Check actions (recovery rolls).
  """

  require Logger
  alias ShotElixir.{Repo, Fights, Characters}
  alias ShotElixir.Fights.Fight

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

      # Apply logic
      if params["success"] do
        character_id = params["character_id"]
        character = Characters.get_character(character_id)

        if character do
          action_values = character.action_values || %{}
          wounds = Map.get(action_values, "Wounds", 0)
          impairments = character.impairments || 0

          # Remove up_check_required status on successful up check
          current_status = character.status || []
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
            {:ok, _} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end
      end

      fight
    end)
    |> case do
      {:ok, fight} -> Fights.touch_fight(fight)
      error -> error
    end
  end
end
