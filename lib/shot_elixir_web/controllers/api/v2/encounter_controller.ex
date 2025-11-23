defmodule ShotElixirWeb.Api.V2.EncounterController do
  use ShotElixirWeb, :controller

  require Logger
  alias ShotElixir.Fights
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Repo
  alias ShotElixir.Services.CombatActionService
  alias ShotElixir.Services.{BoostService, UpCheckService, ChaseActionService}
  alias ShotElixirWeb.CampaignChannel

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/encounters/:id
  # Returns encounter data using EncounterSerializer
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            case Fights.get_fight(id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Encounter not found"})

              fight ->
                if fight.campaign_id == current_user.current_campaign_id do
                  # Preload all necessary associations for encounter serialization
                  fight_with_associations =
                    ShotElixir.Repo.preload(fight,
                      shots: [
                        :character,
                        :vehicle,
                        :character_effects,
                        character: [:faction, :character_schticks, :carries],
                        vehicle: [:faction]
                      ]
                    )

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.EncounterView)
                  |> render("show.json", encounter: fight_with_associations)
                else
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Encounter not found"})
                end
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/encounters/:id/act
  # Handles character/vehicle actions with shot costs and fight events
  def act(conn, %{"id" => fight_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case get_fight(fight_id, current_user.current_campaign_id) do
        {:ok, fight} ->
          if authorize_campaign_modification(fight.campaign_id, current_user) do
            # Save action_id to Fight if provided
            if params["action_id"] do
              Fights.update_fight(fight, %{"action_id" => params["action_id"]})
            end

            case Fights.get_shot(params["shot_id"]) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Shot not found"})

              shot ->
                if shot.fight_id == fight.id do
                  # Default shot count
                  shot_cost = params["shots"] || 3
                  entity = shot.character || shot.vehicle
                  entity_name = (entity && entity.name) || "Unknown"

                  # Update fight timestamp
                  Fights.touch_fight(fight)

                  # Process the action
                  case Fights.act_shot(shot, shot_cost) do
                    {:ok, _updated_shot} ->
                      # Create fight event for the movement
                      case Fights.create_fight_event(%{
                             "fight_id" => fight.id,
                             "event_type" => "movement",
                             "description" => "#{entity_name} spent #{shot_cost} shot(s)",
                             "details" => %{
                               "shot_cost" => shot_cost,
                               "shot_id" => shot.id,
                               "entity_name" => entity_name
                             }
                           }) do
                        {:ok, _event} ->
                          Logger.info(
                            "#{entity_name} spent #{shot_cost} shot(s) in fight #{fight.id}"
                          )

                          # Return updated encounter with all associations
                          fight_with_associations =
                            ShotElixir.Repo.preload(fight,
                              shots: [
                                :character,
                                :vehicle,
                                :character_effects,
                                character: [:faction, :character_schticks, :carries],
                                vehicle: [:faction]
                              ]
                            )

                          # Broadcast encounter update to all connected clients
                          CampaignChannel.broadcast_encounter_update(
                            fight.campaign_id,
                            fight_with_associations
                          )

                          conn
                          |> put_view(ShotElixirWeb.Api.V2.EncounterView)
                          |> render("show.json", encounter: fight_with_associations)

                        {:error, changeset} ->
                          conn
                          |> put_status(:bad_request)
                          |> json(%{errors: translate_errors(changeset)})
                      end

                    {:error, changeset} ->
                      conn
                      |> put_status(:bad_request)
                      |> json(%{errors: translate_errors(changeset)})
                  end
                else
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Shot not found"})
                end
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Encounter not found"})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/encounters/:id/update_initiatives
  # Batch updates shot values with transaction safety
  def update_initiatives(conn, %{"encounter_id" => fight_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case get_fight(fight_id, current_user.current_campaign_id) do
        {:ok, fight} ->
          if authorize_campaign_modification(fight.campaign_id, current_user) do
            shots_data = params["shots"] || []

            Logger.info(
              "🎲 INITIATIVE UPDATE: Updating #{length(shots_data)} shot values for fight #{fight.id}"
            )

            try do
              # Process shots in transaction
              Repo.transaction(fn ->
                Enum.each(shots_data, fn shot_data ->
                  case Fights.get_shot(shot_data["id"]) do
                    nil ->
                      Repo.rollback("Shot #{shot_data["id"]} not found")

                    shot ->
                      if shot.fight_id == fight.id do
                        # Preload associations to get entity name safely
                        shot_with_entity = Repo.preload(shot, [:character, :vehicle])

                        case Fights.update_shot(shot, %{"shot" => shot_data["shot"]}) do
                          {:ok, _updated_shot} ->
                            entity_name =
                              cond do
                                shot_with_entity.character -> shot_with_entity.character.name
                                shot_with_entity.vehicle -> shot_with_entity.vehicle.name
                                true -> "Unknown"
                              end

                            Logger.info(
                              "  Updated shot #{shot.id}: #{entity_name} to shot #{shot_data["shot"]}"
                            )

                          {:error, changeset} ->
                            Repo.rollback(
                              "Failed to update shot #{shot.id}: #{inspect(changeset.errors)}"
                            )
                        end
                      else
                        Repo.rollback("Shot #{shot.id} does not belong to fight #{fight.id}")
                      end
                  end
                end)
              end)

              # Reload fight from database to get fresh shot data after updates
              case get_fight(fight.id, current_user.current_campaign_id) do
                {:ok, fresh_fight} ->
                  # Return updated encounter with all associations
                  fight_with_associations =
                    ShotElixir.Repo.preload(fresh_fight,
                      shots: [
                        :character,
                        :vehicle,
                        :character_effects,
                        character: [:faction, :character_schticks, :carries],
                        vehicle: [:faction]
                      ]
                    )

                  # Broadcast encounter update to all connected clients
                  CampaignChannel.broadcast_encounter_update(
                    fresh_fight.campaign_id,
                    fight_with_associations
                  )

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.EncounterView)
                  |> render("show.json", encounter: fight_with_associations)

                {:error, :not_found} ->
                  conn
                  |> put_status(:internal_server_error)
                  |> json(%{error: "Fight not found after update"})
              end
            rescue
              error ->
                Logger.error("Error updating initiatives: #{inspect(error)}")

                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "Failed to update initiatives"})
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Encounter not found"})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/encounters/:id/apply_combat_action
  # Processes combat actions including boost, up check, and batched combat updates
  def apply_combat_action(conn, %{"encounter_id" => fight_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case get_fight(fight_id, current_user.current_campaign_id) do
        {:ok, fight} ->
          if authorize_campaign_modification(fight.campaign_id, current_user) do
            try do
              # Handle different action types
              result =
                case params["action_type"] do
                  "boost" ->
                    Logger.info("💪 BOOST ACTION: Processing boost for fight #{fight.id}")

                    case BoostService.apply_boost(fight, params) do
                      {:ok, updated_fight} -> updated_fight
                      {:error, reason} -> raise reason
                    end

                  "up_check" ->
                    Logger.info("🎲 UP CHECK ACTION: Processing Up Check for fight #{fight.id}")

                    case UpCheckService.apply_up_check(fight, params) do
                      {:ok, updated_fight} -> updated_fight
                      {:error, reason} -> raise reason
                    end

                  _ ->
                    character_updates = params["character_updates"] || []

                    Logger.info(
                      "🔄 BATCHED COMBAT: Applying #{length(character_updates)} character updates to fight #{fight.id}"
                    )

                    case CombatActionService.apply_combat_action(fight, character_updates) do
                      {:ok, updated_fight} ->
                        Logger.info("✅ Combat action applied successfully")
                        updated_fight

                      {:error, reason} ->
                        Logger.error("❌ Combat action failed: #{inspect(reason)}")
                        raise "Combat action failed: #{inspect(reason)}"
                    end
                end

              # Return updated encounter with all associations
              fight_with_associations =
                ShotElixir.Repo.preload(result,
                  shots: [
                    :character,
                    :vehicle,
                    :character_effects,
                    character: [:faction, :character_schticks, :carries],
                    vehicle: [:faction]
                  ]
                )

              # Broadcast encounter update to all connected clients
              CampaignChannel.broadcast_encounter_update(
                result.campaign_id,
                fight_with_associations
              )

              conn
              |> put_view(ShotElixirWeb.Api.V2.EncounterView)
              |> render("show.json", encounter: fight_with_associations)
            rescue
              error ->
                Logger.error("Error applying combat action: #{inspect(error)}")

                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "Failed to apply combat action"})
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Encounter not found"})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/encounters/:id/apply_chase_action
  # Handles vehicle chase actions
  def apply_chase_action(conn, %{"encounter_id" => fight_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case get_fight(fight_id, current_user.current_campaign_id) do
        {:ok, fight} ->
          if authorize_campaign_modification(fight.campaign_id, current_user) do
            try do
              vehicle_updates = params["vehicle_updates"] || []

              Logger.info(
                "🏎️ CHASE ACTION: Applying #{length(vehicle_updates)} vehicle updates to fight #{fight.id}"
              )

              result =
                case ChaseActionService.apply_chase_action(fight, vehicle_updates) do
                  {:ok, updated_fight} -> updated_fight
                  {:error, reason} -> raise reason
                end

              # Return updated encounter with all associations
              fight_with_associations =
                ShotElixir.Repo.preload(result,
                  shots: [
                    :character,
                    :vehicle,
                    :character_effects,
                    character: [:faction, :character_schticks, :carries],
                    vehicle: [:faction]
                  ]
                )

              # Broadcast encounter update to all connected clients
              CampaignChannel.broadcast_encounter_update(
                result.campaign_id,
                fight_with_associations
              )

              conn
              |> put_view(ShotElixirWeb.Api.V2.EncounterView)
              |> render("show.json", encounter: fight_with_associations)
            rescue
              error ->
                Logger.error("Error applying chase action: #{inspect(error)}")

                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "Failed to apply chase action"})
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Encounter not found"})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # Private helper functions
  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
      Campaigns.is_member?(campaign.id, user.id)
  end

  defp authorize_campaign_modification(campaign_id, user) do
    case Campaigns.get_campaign(campaign_id) do
      nil ->
        false

      campaign ->
        campaign.user_id == user.id || user.admin ||
          (user.gamemaster && Campaigns.is_member?(campaign.id, user.id))
    end
  end

  defp get_fight(fight_id, campaign_id) do
    case Fights.get_fight(fight_id) do
      nil ->
        {:error, :not_found}

      fight ->
        if fight.campaign_id == campaign_id do
          {:ok, fight}
        else
          {:error, :not_found}
        end
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
