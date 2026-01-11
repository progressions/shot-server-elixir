defmodule ShotElixirWeb.Api.V2.SiteController do
  use ShotElixirWeb, :controller

  require Logger

  alias ShotElixir.Sites
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Services.NotionService

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
            result =
              Sites.list_campaign_sites(current_user.current_campaign_id, params, current_user)

            conn
            |> put_view(ShotElixirWeb.Api.V2.SiteView)
            |> render("index.json",
              sites: result.sites,
              meta: result.meta,
              factions: result.factions
            )
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
              conn
              |> put_view(ShotElixirWeb.Api.V2.SiteView)
              |> render("show.json", site: site)
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
                # Handle image upload if present
                case conn.params["image"] do
                  %Plug.Upload{} = upload ->
                    case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                      {:ok, upload_result} ->
                        case ShotElixir.ActiveStorage.attach_image("Site", site.id, upload_result) do
                          {:ok, _attachment} ->
                            site = Sites.get_site(site.id)

                            conn
                            |> put_status(:created)
                            |> put_view(ShotElixirWeb.Api.V2.SiteView)
                            |> render("show.json", site: site)

                          {:error, _changeset} ->
                            conn
                            |> put_status(:created)
                            |> put_view(ShotElixirWeb.Api.V2.SiteView)
                            |> render("show.json", site: site)
                        end

                      {:error, _reason} ->
                        conn
                        |> put_status(:created)
                        |> put_view(ShotElixirWeb.Api.V2.SiteView)
                        |> render("show.json", site: site)
                    end

                  _ ->
                    conn
                    |> put_status(:created)
                    |> put_view(ShotElixirWeb.Api.V2.SiteView)
                    |> render("show.json", site: site)
                end

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> put_view(ShotElixirWeb.Api.V2.SiteView)
                |> render("error.json", changeset: changeset)
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
                # Handle image upload if present
                case conn.params["image"] do
                  %Plug.Upload{} = upload ->
                    # Upload image to ImageKit
                    case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                      {:ok, upload_result} ->
                        # Attach image to site via ActiveStorage
                        case ShotElixir.ActiveStorage.attach_image("Site", site.id, upload_result) do
                          {:ok, _attachment} ->
                            # Reload site to get fresh data after image attachment
                            site = Sites.get_site(site.id)
                            # Continue with site update
                            case Sites.update_site(site, parsed_params) do
                              {:ok, site} ->
                                conn
                                |> put_view(ShotElixirWeb.Api.V2.SiteView)
                                |> render("show.json", site: site)

                              {:error, changeset} ->
                                conn
                                |> put_status(:unprocessable_entity)
                                |> put_view(ShotElixirWeb.Api.V2.SiteView)
                                |> render("error.json", changeset: changeset)
                            end

                          {:error, changeset} ->
                            conn
                            |> put_status(:unprocessable_entity)
                            |> put_view(ShotElixirWeb.Api.V2.SiteView)
                            |> render("error.json", changeset: changeset)
                        end

                      {:error, reason} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
                    end

                  _ ->
                    # No image upload, just update site
                    case Sites.update_site(site, parsed_params) do
                      {:ok, site} ->
                        conn
                        |> put_view(ShotElixirWeb.Api.V2.SiteView)
                        |> render("show.json", site: site)

                      {:error, changeset} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> put_view(ShotElixirWeb.Api.V2.SiteView)
                        |> render("error.json", changeset: changeset)
                    end
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
              # Remove image from ActiveStorage
              case ShotElixir.ActiveStorage.delete_image("Site", site.id) do
                {:ok, _} ->
                  # Reload site to get fresh data after image removal
                  updated_site = Sites.get_site(site.id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.SiteView)
                  |> render("show.json", site: updated_site)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.SiteView)
                  |> render("error.json", changeset: changeset)
              end
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

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.SiteView)
                  |> render("show.json", site: site)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.SiteView)
                  |> render("error.json", changeset: changeset)
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

  # POST /api/v2/sites/:id/duplicate
  def duplicate(conn, %{"site_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user),
         %{} = site <- Sites.get_site(id),
         true <- site.campaign_id == campaign_id,
         campaign <- Campaigns.get_campaign(campaign_id),
         true <- authorize_campaign_modification(campaign, current_user),
         {:ok, new_site} <- Sites.duplicate_site(site) do
      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.SiteView)
      |> render("show.json", site: new_site)
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Site not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only campaign owners, admins, or gamemasters can duplicate sites"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.SiteView)
        |> render("error.json", changeset: changeset)
    end
  end

  # POST /api/v2/sites/:site_id/sync
  def sync(conn, %{"site_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Sites.get_site(id) do
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
              case NotionService.sync_site(site) do
                {:ok, :unlinked} ->
                  # Page was deleted in Notion, reload site to get cleared notion_page_id
                  updated_site = Sites.get_site(id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.SiteView)
                  |> render("show.json", site: updated_site)

                {:ok, updated_site} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.SiteView)
                  |> render("show.json", site: updated_site)

                {:error, {:notion_api_error, code, message}} ->
                  Logger.error("Notion API error syncing site: #{code} - #{message}")

                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to sync to Notion: #{message}"})

                {:error, reason} ->
                  Logger.error("Failed to sync site to Notion: #{inspect(reason)}")

                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to sync to Notion"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only campaign owners, admins, or gamemasters can sync sites"})
            end
        end
    end
  end

  defp ensure_campaign(user) do
    if user.current_campaign_id do
      {:ok, user.current_campaign_id}
    else
      {:error, :no_campaign}
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
