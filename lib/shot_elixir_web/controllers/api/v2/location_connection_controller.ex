defmodule ShotElixirWeb.Api.V2.LocationConnectionController do
  @moduledoc """
  Controller for managing location connections (edges between locations).
  Used in the visual location editor to show paths between areas.
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Sites
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixirWeb.FightChannel

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/fights/:fight_id/location_connections
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
              connections = Fights.list_fight_location_connections(fight_id)

              conn
              |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
              |> render("index.json", connections: connections)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # GET /api/v2/sites/:site_id/location_connections
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
              connections = Fights.list_site_location_connections(site_id)

              conn
              |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
              |> render("index.json", connections: connections)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # GET /api/v2/location_connections/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_location_connection(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Connection not found"})

      connection ->
        campaign_id = get_campaign_id(connection)

        case Campaigns.get_campaign(campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Connection not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              conn
              |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
              |> render("show.json", connection: connection)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # POST /api/v2/fights/:fight_id/location_connections
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
              connection_params = extract_connection_params(params)

              case Fights.create_fight_location_connection(fight_id, connection_params) do
                {:ok, connection} ->
                  # Broadcast connection creation
                  FightChannel.broadcast_fight_update(fight_id, "location_connection_created", %{
                    connection: serialize_connection(connection)
                  })

                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
                  |> render("show.json", connection: connection)

                {:error, %Ecto.Changeset{} = changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
                  |> render("error.json", changeset: changeset)

                {:error, reason} when is_binary(reason) ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: reason})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can create connections"})
            end
        end
    end
  end

  # POST /api/v2/sites/:site_id/location_connections
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
              connection_params = extract_connection_params(params)

              case Fights.create_site_location_connection(site_id, connection_params) do
                {:ok, connection} ->
                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
                  |> render("show.json", connection: connection)

                {:error, %Ecto.Changeset{} = changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.LocationConnectionView)
                  |> render("error.json", changeset: changeset)

                {:error, reason} when is_binary(reason) ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: reason})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can create connections"})
            end
        end
    end
  end

  # DELETE /api/v2/location_connections/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_location_connection(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Connection not found"})

      connection ->
        campaign_id = get_campaign_id(connection)

        case Campaigns.get_campaign(campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Connection not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Get fight_id before deletion for broadcast
              fight_id = connection.from_location && connection.from_location.fight_id

              case Fights.delete_location_connection(connection) do
                {:ok, _} ->
                  # Broadcast connection deletion if it was in a fight
                  if fight_id do
                    FightChannel.broadcast_fight_update(
                      fight_id,
                      "location_connection_deleted",
                      %{
                        connection_id: id
                      }
                    )
                  end

                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete connection"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can delete connections"})
            end
        end
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp extract_connection_params(params) do
    case params do
      %{"connection" => connection_data} when is_map(connection_data) ->
        connection_data

      _ ->
        params
        |> Map.take(["from_location_id", "to_location_id", "bidirectional", "label"])
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
    end
  end

  defp get_campaign_id(%{from_location: %{fight_id: fight_id}}) when not is_nil(fight_id) do
    case Fights.get_fight(fight_id) do
      nil -> nil
      fight -> fight.campaign_id
    end
  end

  defp get_campaign_id(%{from_location: %{site_id: site_id}}) when not is_nil(site_id) do
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

  defp serialize_connection(connection) do
    # Use the view's rendering logic to avoid duplication
    ShotElixirWeb.Api.V2.LocationConnectionView.render("show.json", %{connection: connection})
  end
end
