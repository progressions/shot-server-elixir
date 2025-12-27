defmodule ShotElixir.Services.ChaseActionService do
  @moduledoc """
  Handles vehicle chase actions.
  """

  require Logger
  alias ShotElixir.{Repo, Fights, Vehicles, Chases}
  alias ShotElixir.Fights.{Fight, Shot}

  # These chase metrics should be additive (add to existing value, not replace)
  @additive_fields ["Chase Points", "Condition Points"]

  def apply_chase_action(%Fight{} = fight, vehicle_updates) do
    Logger.info("Applying chase action for fight #{fight.id}")

    Repo.transaction(fn ->
      # Enrich updates with vehicle names for the event details
      enriched_updates = enrich_vehicle_updates(vehicle_updates)

      # Record the event with enriched details
      case Fights.create_fight_event(
             %{
               "fight_id" => fight.id,
               "event_type" => "chase_action",
               "description" => "Chase action",
               "details" => %{"vehicle_updates" => enriched_updates}
             },
             broadcast: false
           ) do
        {:ok, _event} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end

      # Apply updates
      case apply_updates(fight, vehicle_updates) do
        :ok -> fight
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, fight} -> Fights.touch_fight(fight)
      error -> error
    end
  end

  # Enrich vehicle updates with vehicle names for event details
  # Fetches all vehicles in a single query to avoid N+1 query issues
  defp enrich_vehicle_updates(vehicle_updates) do
    # Collect all vehicle IDs
    vehicle_ids =
      vehicle_updates
      |> Enum.map(fn update -> update["vehicle_id"] || update["id"] end)
      |> Enum.reject(&is_nil/1)

    # Fetch all vehicles in a single query
    vehicles = Vehicles.list_vehicles_by_ids(vehicle_ids)
    vehicles_map = Map.new(vehicles, fn v -> {v.id, v} end)

    # Enrich each update with the vehicle name
    Enum.map(vehicle_updates, fn update ->
      vehicle_id = update["vehicle_id"] || update["id"]

      vehicle_name =
        case Map.get(vehicles_map, vehicle_id) do
          nil -> "Vehicle"
          vehicle -> vehicle.name
        end

      Map.put(update, "vehicle_name", vehicle_name)
    end)
  end

  defp apply_updates(fight, vehicle_updates) do
    Enum.reduce_while(vehicle_updates, :ok, fn update, _ ->
      vehicle_id = update["vehicle_id"] || update["id"]

      if vehicle_id do
        vehicle = Vehicles.get_vehicle(vehicle_id)

        if vehicle do
          # Build merged action_values including Position if provided
          merged_av = build_action_values(vehicle, update)
          attrs = Map.put(update, "action_values", merged_av)

          case Vehicles.update_vehicle(vehicle, attrs) do
            {:ok, updated_vehicle} ->
              # Update chase relationship position if provided
              case maybe_update_chase_position(fight, updated_vehicle, update) do
                :ok ->
                  # Spend shots for the character if shot_cost and character_id are provided
                  case maybe_spend_shots(fight, update) do
                    :ok -> {:cont, :ok}
                    {:error, reason} -> {:halt, {:error, reason}}
                  end

                {:error, reason} ->
                  {:halt, {:error, reason}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
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

  # Build merged action_values with additive handling for Chase Points and Condition Points
  # Position is NOT stored in action_values - it's on the chase_relationship
  defp build_action_values(vehicle, update) do
    base_av = vehicle.action_values || %{}
    update_av = update["action_values"] || %{}

    # For additive fields (Chase Points, Condition Points), add to existing value
    # For other fields, use the new value directly
    Enum.reduce(update_av, base_av, fn {key, value}, acc ->
      if key in @additive_fields do
        current_value = Map.get(acc, key, 0) || 0
        new_value = parse_integer(value)

        Logger.info(
          "Adding #{new_value} to #{key} (current: #{current_value}) = #{current_value + new_value}"
        )

        Map.put(acc, key, current_value + new_value)
      else
        Map.put(acc, key, value)
      end
    end)
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_integer(_), do: 0

  # Update the chase relationship position between two vehicle shots
  # The "position" (near/far) is stored on the ChaseRelationship, not the vehicle
  # Chase relationships use shot IDs (vehicle instances) not vehicle template IDs
  defp maybe_update_chase_position(fight, _vehicle, update) do
    position = update["position"]
    # Use shot_id (vehicle instance) instead of vehicle_id (template)
    shot_id = update["shot_id"]
    target_shot_id = update["target_shot_id"]
    role = update["role"] || "pursuer"

    if position && shot_id && target_shot_id do
      # Validate both shots exist and belong to this fight
      pursuer_shot = Repo.get(Shot, shot_id)
      evader_shot = Repo.get(Shot, target_shot_id)

      if pursuer_shot && evader_shot &&
           pursuer_shot.fight_id == fight.id && evader_shot.fight_id == fight.id do
        Logger.info(
          "Updating chase position: shot #{shot_id} -> #{target_shot_id}, position: #{position}, role: #{role}"
        )

        # Determine pursuer/evader based on role
        {final_pursuer_id, final_evader_id} =
          if role == "evader" do
            {target_shot_id, shot_id}
          else
            {shot_id, target_shot_id}
          end

        # Find or create the chase relationship using shot IDs
        case Chases.get_or_create_relationship(fight.id, final_pursuer_id, final_evader_id) do
          {:ok, relationship} ->
            # Update the position
            case Chases.update_relationship(relationship, %{position: position}) do
              {:ok, updated_rel} ->
                Logger.info(
                  "Updated chase relationship #{updated_rel.id} position to #{updated_rel.position}"
                )

                :ok

              {:error, reason} ->
                Logger.error("Failed to update chase relationship position: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, reason} ->
            Logger.error("Failed to get/create chase relationship: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Logger.warning(
          "Shot(s) not found or not in fight: shot_id=#{shot_id}, target_shot_id=#{target_shot_id}"
        )

        :ok
      end
    else
      :ok
    end
  end

  # Spend shots for the driver if shot_cost and driver_shot_id are present
  # Uses driver_shot_id (the character's shot record) instead of character_id
  # because a character can appear multiple times in a fight at different shot positions
  defp maybe_spend_shots(fight, update) do
    driver_shot_id = update["driver_shot_id"]
    shot_cost = update["shot_cost"]

    if driver_shot_id && shot_cost && shot_cost > 0 do
      Logger.info(
        "Spending #{shot_cost} shots for driver shot #{driver_shot_id} in fight #{fight.id}"
      )

      # Get the shot directly by ID (no need to query by character_id)
      shot = Repo.get(Shot, driver_shot_id)

      if shot && shot.fight_id == fight.id do
        case Fights.act_shot(shot, shot_cost) do
          {:ok, _updated_shot} ->
            Logger.info("Successfully spent #{shot_cost} shots for driver shot #{driver_shot_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to spend shots: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Logger.warning("No shot found with id #{driver_shot_id} in fight #{fight.id}")
        :ok
      end
    else
      :ok
    end
  end
end
