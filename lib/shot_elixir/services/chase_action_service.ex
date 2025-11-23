defmodule ShotElixir.Services.ChaseActionService do
  @moduledoc """
  Handles vehicle chase actions.
  """

  require Logger
  alias ShotElixir.{Repo, Fights, Vehicles}
  alias ShotElixir.Fights.Fight

  def apply_chase_action(%Fight{} = fight, vehicle_updates) do
    Logger.info("Applying chase action for fight #{fight.id}")

    Repo.transaction(fn ->
      # Record the event
      case Fights.create_fight_event(
             %{
               "fight_id" => fight.id,
               "event_type" => "chase_action",
               "description" => "Chase action performed with #{length(vehicle_updates)} updates",
               "details" => %{"updates_count" => length(vehicle_updates)}
             },
             broadcast: false
           ) do
        {:ok, _event} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      # Apply updates
      case apply_updates(vehicle_updates) do
        :ok -> fight
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, fight} -> Fights.touch_fight(fight)
      error -> error
    end
  end

  defp apply_updates(vehicle_updates) do
    Enum.reduce_while(vehicle_updates, :ok, fn update, _ ->
      vehicle_id = update["vehicle_id"] || update["id"]

      if vehicle_id do
        vehicle = Vehicles.get_vehicle(vehicle_id)

        if vehicle do
          attrs =
            if update["action_values"] do
              merged_av = Map.merge(vehicle.action_values || %{}, update["action_values"])
              Map.put(update, "action_values", merged_av)
            else
              update
            end

          case Vehicles.update_vehicle(vehicle, attrs) do
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        else
          # Vehicle not found, skip
          {:cont, :ok}
        end
      else
        # No ID, skip
        {:cont, :ok}
      end
    end)
  end
end
