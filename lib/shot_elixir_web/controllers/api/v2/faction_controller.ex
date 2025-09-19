defmodule ShotElixirWeb.Api.V2.FactionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Factions
  alias ShotElixir.Campaigns

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/factions
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            result =
              Factions.list_campaign_factions(
                current_user.current_campaign_id,
                params,
                current_user
              )

            render(conn, :index, factions: result)
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

  # GET /api/v2/factions/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Factions.get_faction(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      faction ->
        # Check campaign access
        case Campaigns.get_campaign(faction.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Faction not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              render(conn, :show, faction: faction)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Faction not found"})
            end
        end
    end
  end

  # POST /api/v2/factions
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"faction" => faction_data} when is_binary(faction_data) ->
          case Jason.decode(faction_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid faction data format"})
              |> halt()
          end

        %{"faction" => faction_data} when is_map(faction_data) ->
          faction_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Faction parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # Add campaign_id from current campaign
      faction_params = Map.put(parsed_params, "campaign_id", current_user.current_campaign_id)

      # Verify campaign access
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No active campaign selected"})

        campaign ->
          if authorize_campaign_modification(campaign, current_user) do
            case Factions.create_faction(faction_params) do
              {:ok, faction} ->
                conn
                |> put_status(:created)
                |> render(:show, faction: faction)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> render(:error, changeset: changeset)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only gamemaster can create factions"})
          end
      end
    end
  end

  # PATCH/PUT /api/v2/factions/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Factions.get_faction(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      faction ->
        # Check campaign access
        case Campaigns.get_campaign(faction.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Faction not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Handle JSON string parsing like Rails
              parsed_params =
                case params do
                  %{"faction" => faction_data} when is_binary(faction_data) ->
                    case Jason.decode(faction_data) do
                      {:ok, decoded} ->
                        decoded

                      {:error, _} ->
                        conn
                        |> put_status(:bad_request)
                        |> json(%{error: "Invalid faction data format"})
                        |> halt()
                    end

                  %{"faction" => faction_data} when is_map(faction_data) ->
                    faction_data

                  _ ->
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Faction parameters required"})
                    |> halt()
                end

              if conn.halted do
                conn
              else
                case Factions.update_faction(faction, parsed_params) do
                  {:ok, faction} ->
                    render(conn, :show, faction: faction)

                  {:error, changeset} ->
                    conn
                    |> put_status(:unprocessable_entity)
                    |> render(:error, changeset: changeset)
                end
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Faction not found"})
            end
        end
    end
  end

  # DELETE /api/v2/factions/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Factions.get_faction(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      faction ->
        # Check campaign access
        case Campaigns.get_campaign(faction.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Faction not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Factions.delete_faction(faction) do
                {:ok, _faction} ->
                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete faction"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Faction not found"})
            end
        end
    end
  end

  # DELETE /api/v2/factions/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Factions.get_faction(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      faction ->
        # Check campaign access
        case Campaigns.get_campaign(faction.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Faction not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # TODO: Implement image removal when Active Storage equivalent is added
              # For now, just return the faction
              render(conn, :show, faction: faction)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Faction not found"})
            end
        end
    end
  end

  # Private helper functions
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
