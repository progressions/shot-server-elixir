defmodule ShotElixirWeb.Api.V2.SiteController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Sites
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/sites
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
            result = Sites.list_campaign_sites(current_user.current_campaign_id, params, current_user)
            render(conn, :index, data: result)
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

  # GET /api/v2/sites/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        # Check campaign access
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              render(conn, :show, site: site)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Site not found"})
            end
        end
    end
  end

  # POST /api/v2/sites
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"site" => site_data} when is_binary(site_data) ->
          case Jason.decode(site_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid site data format"})
              |> halt()
          end

        %{"site" => site_data} when is_map(site_data) ->
          site_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Site parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # Add campaign_id from current campaign
      site_params = Map.put(parsed_params, "campaign_id", current_user.current_campaign_id)

      # Verify campaign access
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No active campaign selected"})

        campaign ->
          if authorize_campaign_modification(campaign, current_user) do
            case Sites.create_site(site_params) do
              {:ok, site} ->
                conn
                |> put_status(:created)
                |> render(:show, site: site)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> render(:error, changeset: changeset)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only gamemaster can create sites"})
          end
      end
    end
  end

  # PATCH/PUT /api/v2/sites/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        # Check campaign access
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Handle JSON string parsing like Rails
              parsed_params =
                case params do
                  %{"site" => site_data} when is_binary(site_data) ->
                    case Jason.decode(site_data) do
                      {:ok, decoded} ->
                        decoded

                      {:error, _} ->
                        conn
                        |> put_status(:bad_request)
                        |> json(%{error: "Invalid site data format"})
                        |> halt()
                    end

                  %{"site" => site_data} when is_map(site_data) ->
                    site_data

                  _ ->
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Site parameters required"})
                    |> halt()
                end

              if conn.halted do
                conn
              else
                case Sites.update_site(site, parsed_params) do
                  {:ok, site} ->
                    render(conn, :show, site: site)

                  {:error, changeset} ->
                    conn
                    |> put_status(:unprocessable_entity)
                    |> render(:error, changeset: changeset)
                end
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Site not found"})
            end
        end
    end
  end

  # DELETE /api/v2/sites/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        # Check campaign access
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Sites.delete_site(site) do
                {:ok, _site} ->
                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete site"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Site not found"})
            end
        end
    end
  end

  # DELETE /api/v2/sites/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        # Check campaign access
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # TODO: Implement image removal when Active Storage equivalent is added
              # For now, just return the site
              render(conn, :show, site: site)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Site not found"})
            end
        end
    end
  end

  # POST /api/v2/sites/:id/attune
  def attune(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    id = params["id"] || params["site_id"]
    character_id = params["character_id"]

    case Sites.get_site(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        # Check campaign access
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Sites.create_attunement(%{"site_id" => id, "character_id" => character_id}) do
                {:ok, _attunement} ->
                  site = Sites.get_site!(id)
                  render(conn, :show, site: site)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> render(:error, changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Site not found"})
            end
        end
    end
  end

  # DELETE /api/v2/sites/:id/attune/:character_id
  def unattune(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    id = params["id"] || params["site_id"]
    character_id = params["character_id"]

    case Sites.get_site(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      site ->
        # Check campaign access
        case Campaigns.get_campaign(site.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Site not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              attunement = Sites.get_attunement_by_character_and_site(character_id, id)

              case attunement do
                nil ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Attunement not found"})

                _ ->
                  case Sites.delete_attunement(attunement) do
                    {:ok, _} ->
                      send_resp(conn, :no_content, "")

                    {:error, _} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> json(%{error: "Failed to remove attunement"})
                  end
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Site not found"})
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
