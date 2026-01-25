defmodule ShotElixirWeb.Api.V2.ShotController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Fights.Shot
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Discord.Notifications

  action_fallback ShotElixirWeb.FallbackController

  # PATCH/PUT /api/v2/fights/:fight_id/shots/:id
  def update(conn, %{"fight_id" => fight_id, "id" => id, "shot" => shot_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Shot{} = shot <- Fights.get_shot(id),
         %{} = fight <- Fights.get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user) do
      # Handle driver linkage if updating a vehicle shot
      if shot.vehicle_id && Map.has_key?(shot_params, "driver_id") do
        handle_driver_linkage(fight, shot, shot_params["driver_id"])
      end

      case Fights.update_shot(shot, shot_params) do
        {:ok, _shot} ->
          Notifications.maybe_notify_discord(fight)
          json(conn, %{success: true})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(changeset.errors)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update shots"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})
    end
  end

  # DELETE /api/v2/fights/:fight_id/shots/:id
  def delete(conn, %{"fight_id" => fight_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Shot{} = shot <- Fights.get_shot(id),
         %{} = fight <- Fights.get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user),
         {:ok, _shot} <- Fights.delete_shot(shot) do
      Notifications.maybe_notify_discord(fight)
      send_resp(conn, :no_content, "")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete shots"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete shot"})
    end
  end

  # POST /api/v2/fights/:fight_id/shots/:id/assign_driver
  def assign_driver(conn, %{
        "fight_id" => fight_id,
        "id" => id,
        "driver_shot_id" => driver_shot_id
      }) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Shot{} = shot <- Fights.get_shot(id),
         %{} = fight <- Fights.get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user) do
      # Validate this is a vehicle shot
      if !shot.vehicle_id do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Shot must contain a vehicle"})
      else
        driver_shot = Fights.get_shot(driver_shot_id)

        # Validate driver shot exists
        if !driver_shot do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Driver shot not found"})
        else
          # Validate driver shot contains a character
          if !driver_shot.character_id do
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Shot must contain a character to be a driver"})
          else
            # Clear any existing driver for this vehicle
            Fights.clear_vehicle_drivers(fight.id, shot.id)

            # Assign the new driver
            case Fights.assign_driver(driver_shot, shot.id) do
              {:ok, _driver_shot} ->
                json(conn, %{success: true, message: "Driver assigned successfully"})

              {:error, _changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to assign driver"})
            end
          end
        end
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can assign drivers"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})
    end
  end

  # DELETE /api/v2/fights/:fight_id/shots/:id/remove_driver
  def remove_driver(conn, %{"fight_id" => fight_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Shot{} = shot <- Fights.get_shot(id),
         %{} = fight <- Fights.get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user) do
      # Validate this is a vehicle shot
      if !shot.vehicle_id do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Shot must contain a vehicle"})
      else
        # Clear any driver for this vehicle
        Fights.clear_vehicle_drivers(fight.id, shot.id)

        json(conn, %{success: true, message: "Driver removed successfully"})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can remove drivers"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})
    end
  end

  # POST /api/v2/shots/:id/set_location
  # Any campaign member can set locations (not gamemaster-only)
  def set_location(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)
    location_name = params["location_name"]

    with %Shot{} = shot <- Fights.get_shot(id),
         %{} = fight <- Fights.get_fight(shot.fight_id),
         %{} = campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_campaign_member(campaign, current_user) do
      case Fights.set_shot_location(shot, location_name) do
        {:ok, updated_shot, created} ->
          # Broadcast the full encounter update to CampaignChannel
          # This is what the frontend actually listens for
          fight_with_associations = Fights.get_fight_with_shots(fight.id)
          ShotElixirWeb.CampaignChannel.broadcast_encounter_update(
            campaign.id,
            fight_with_associations
          )

          conn
          |> put_view(ShotElixirWeb.Api.V2.ShotView)
          |> render("set_location.json", shot: updated_shot, created: created)

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to set location", reason: inspect(reason)})
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot not found"})

      {:error, :not_member} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You must be a campaign member to set locations"})
    end
  end

  # Private helper functions
  defp validate_shot_belongs_to_fight(shot, fight) do
    if shot.fight_id == fight.id do
      :ok
    else
      {:error, :mismatch}
    end
  end

  defp authorize_fight_edit(fight, user) do
    campaign = Campaigns.get_campaign(fight.campaign_id)

    # For cross-campaign security, return :not_found for non-members, :forbidden for members
    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      user.gamemaster && Campaigns.is_member?(campaign.id, user.id) -> :ok
      Campaigns.is_member?(campaign.id, user.id) -> {:error, :forbidden}
      true -> {:error, :not_found}
    end
  end

  defp handle_driver_linkage(fight, shot, driver_id) do
    # Clear any existing driver linkage for this vehicle
    Fights.clear_vehicle_drivers(fight.id, shot.id)

    # Set up new driver linkage if driver_id is provided and not empty
    if driver_id && driver_id != "" do
      driver_shot = Fights.get_shot(driver_id)

      if driver_shot && driver_shot.character_id do
        # Link the driver shot to this vehicle
        Fights.assign_driver(driver_shot, shot.id)
      end
    end
  end

  defp authorize_campaign_member(campaign, user) do
    if Campaigns.is_member?(campaign.id, user.id) || campaign.user_id == user.id || user.admin do
      :ok
    else
      {:error, :not_member}
    end
  end

end
