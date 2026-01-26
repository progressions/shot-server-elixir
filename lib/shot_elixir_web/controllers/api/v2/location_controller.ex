defmodule ShotElixirWeb.Api.V2.LocationController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Sites
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixirWeb.FightChannel
  alias ShotElixirWeb.CampaignChannel

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/fights/:fight_id/locations
  def index_for_fight(conn, %{"fight_id" => fight_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_fight(fight_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      fight ->
        case Campaigns.get_campaign(fight.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Fight not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              locations = Fights.list_fight_locations(fight_id)

              conn
              |> put_view(ShotElixirWeb.Api.V2.LocationView)
              |> render("index.json", locations: locations)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # GET /api/v2/sites/:site_id/locations
  def index_for_site(conn, %{"site_id" => site_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(site_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              locations = Fights.list_site_locations(site_id)

              conn
              |> put_view(ShotElixirWeb.Api.V2.LocationView)
              |> render("index.json", locations: locations)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # GET /api/v2/locations/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_location(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Location not found"})

      location ->
        campaign_id = get_campaign_id(location)

        case Campaigns.get_campaign(campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Location not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              conn
              |> put_view(ShotElixirWeb.Api.V2.LocationView)
              |> render("show.json", location: location)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # POST /api/v2/fights/:fight_id/locations
  def create_for_fight(conn, %{"fight_id" => fight_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_fight(fight_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      fight ->
        case Campaigns.get_campaign(fight.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Fight not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              location_params = extract_location_params(params)

              case Fights.create_fight_location(fight_id, location_params) do
                {:ok, location} ->
                  location = Fights.get_location(location.id)

                  # Broadcast location creation to connected clients
                  FightChannel.broadcast_location_created(fight_id, location)

                  # Broadcast full locations update to campaign channel for dynamic UI updates
                  CampaignChannel.broadcast_locations_update(campaign.id, fight_id)

                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.LocationView)
                  |> render("show.json", location: location)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.LocationView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can create locations"})
            end
        end
    end
  end

  # POST /api/v2/sites/:site_id/locations
  def create_for_site(conn, %{"site_id" => site_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(site_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              location_params = extract_location_params(params)

              case Fights.create_site_location(site_id, location_params) do
                {:ok, location} ->
                  location = Fights.get_location(location.id)

                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.LocationView)
                  |> render("show.json", location: location)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.LocationView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can create locations"})
            end
        end
    end
  end

  # PATCH /api/v2/locations/:id
  def update(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_location(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Location not found"})

      location ->
        campaign_id = get_campaign_id(location)

        case Campaigns.get_campaign(campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Location not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              location_params = extract_location_params(params)

              case Fights.update_location(location, location_params) do
                {:ok, updated_location} ->
                  updated_location = Fights.get_location(updated_location.id)

                  # Broadcast location update if it belongs to a fight
                  if updated_location.fight_id do
                    FightChannel.broadcast_location_updated(
                      updated_location.fight_id,
                      updated_location
                    )

                    # Broadcast full locations update to campaign channel for dynamic UI updates
                    CampaignChannel.broadcast_locations_update(
                      campaign.id,
                      updated_location.fight_id
                    )
                  end

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.LocationView)
                  |> render("show.json", location: updated_location)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.LocationView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can update locations"})
            end
        end
    end
  end

  # DELETE /api/v2/locations/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_location(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Location not found"})

      location ->
        campaign_id = get_campaign_id(location)

        case Campaigns.get_campaign(campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Location not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Store fight_id before deletion for broadcasting
              fight_id = location.fight_id

              case Fights.delete_location(location) do
                {:ok, deleted_location} ->
                  # Broadcast updates if it belonged to a fight
                  if fight_id do
                    FightChannel.broadcast_location_deleted(fight_id, deleted_location.id)

                    # Broadcast full locations update to campaign channel for dynamic UI updates
                    CampaignChannel.broadcast_locations_update(campaign.id, fight_id)

                    # Broadcast encounter update so shots move to Unassigned in the UI
                    # (database ON DELETE SET NULL already set location_id to nil)
                    fight_with_associations = Fights.get_fight_with_shots(fight_id)

                    CampaignChannel.broadcast_encounter_update(
                      campaign.id,
                      fight_with_associations
                    )
                  end

                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete location"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can delete locations"})
            end
        end
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp extract_location_params(params) do
    case params do
      %{"location" => location_data} when is_map(location_data) ->
        location_data

      %{"location" => location_data} when is_binary(location_data) ->
        case Jason.decode(location_data) do
          {:ok, decoded} ->
            decoded

          {:error, _} ->
            raise Plug.BadRequestError, message: "Invalid location data format"
        end

      _ ->
        # Extract location fields directly from params
        params
        |> Map.take(["name", "description", "color", "image_url"])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    end
  end

  defp get_campaign_id(%{fight: %{campaign_id: id}}) when not is_nil(id), do: id
  defp get_campaign_id(%{site: %{campaign_id: id}}) when not is_nil(id), do: id

  defp get_campaign_id(%{fight_id: fight_id}) when not is_nil(fight_id) do
    case Fights.get_fight(fight_id) do
      nil -> nil
      fight -> fight.campaign_id
    end
  end

  defp get_campaign_id(%{site_id: site_id}) when not is_nil(site_id) do
    case Sites.get_site(site_id) do
      nil -> nil
      site -> site.campaign_id
    end
  end

  defp get_campaign_id(_), do: nil

  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
      Campaigns.is_member?(campaign.id, user.id)
  end

  defp authorize_campaign_modification(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id))
  end
end
