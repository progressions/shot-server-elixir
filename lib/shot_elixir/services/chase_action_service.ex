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
      Enum.each(vehicle_updates, fn update ->
        vehicle_id = update["vehicle_id"] || update["id"]

        if vehicle_id do
          vehicle = Vehicles.get_vehicle(vehicle_id)

          if vehicle do
            # Merge action_values to prevent data loss if present
            attrs =
              if update["action_values"] do
                merged_av = Map.merge(vehicle.action_values || %{}, update["action_values"])
                Map.put(update, "action_values", merged_av)
              else
                update
              end

            case Vehicles.update_vehicle(vehicle, attrs) do
              {:ok, _} -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
          end
        end
      end)

      fight
    end)
    |> case do
      {:ok, fight} -> Fights.touch_fight(fight)
      error -> error
    end
  end
end
