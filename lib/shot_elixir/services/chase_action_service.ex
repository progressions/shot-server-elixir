defmodule ShotElixir.Services.ChaseActionService do
  @moduledoc """
  Handles vehicle chase actions.
  """

  require Logger
  import Ecto.Query
  alias ShotElixir.{Repo, Fights, Vehicles, Chases}
  alias ShotElixir.Fights.{Fight, Shot}

  # These chase metrics should be additive (add to existing value, not replace)
  @additive_fields ["Chase Points", "Condition Points"]

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

  # Update the chase relationship position between two vehicles
  # The "position" (near/far) is stored on the ChaseRelationship, not the vehicle
  defp maybe_update_chase_position(fight, vehicle, update) do
    position = update["position"]
    target_vehicle_id = update["target_vehicle_id"]
    role = update["role"] || "pursuer"

    if position && target_vehicle_id do
      # Validate target vehicle exists and belongs to the same campaign
      target_vehicle = Vehicles.get_vehicle(target_vehicle_id)

      if target_vehicle && target_vehicle.campaign_id == fight.campaign_id do
        Logger.info(
          "Updating chase position: vehicle #{vehicle.id} -> #{target_vehicle_id}, position: #{position}, role: #{role}"
        )

        # Determine pursuer/evader based on role
        {pursuer_id, evader_id} =
          if role == "evader" do
            {target_vehicle_id, vehicle.id}
          else
            {vehicle.id, target_vehicle_id}
          end

        # Find or create the chase relationship
        case Chases.get_or_create_relationship(fight.id, pursuer_id, evader_id) do
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
        Logger.warning("Target vehicle #{target_vehicle_id} not found or not in fight's campaign")

        :ok
      end
    else
      :ok
    end
  end

  # Spend shots for the character if shot_cost and character_id are present
  defp maybe_spend_shots(fight, update) do
    character_id = update["character_id"]
    shot_cost = update["shot_cost"]

    if character_id && shot_cost && shot_cost > 0 do
      Logger.info(
        "Spending #{shot_cost} shots for character #{character_id} in fight #{fight.id}"
      )

      # Find the shot for this character in this fight
      shot =
        Repo.one(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character_id
        )

      if shot do
        case Fights.act_shot(shot, shot_cost) do
          {:ok, _updated_shot} ->
            Logger.info("Successfully spent #{shot_cost} shots for character #{character_id}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to spend shots: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Logger.warning("No shot found for character #{character_id} in fight #{fight.id}")
        :ok
      end
    else
      :ok
    end
  end
end
