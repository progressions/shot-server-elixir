defmodule ShotElixirWeb.Api.V2.FactionController do
  use ShotElixirWeb, :controller

  require Logger

  alias ShotElixir.Factions
  alias ShotElixir.Campaigns
  alias ShotElixir.Services.NotionService

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

            conn
            |> put_view(ShotElixirWeb.Api.V2.FactionView)
            |> render("index.json", factions: result.factions, meta: result.meta)
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
              conn
              |> put_view(ShotElixirWeb.Api.V2.FactionView)
              |> render("show.json", faction: faction)
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
                # Handle image upload if present
                case conn.params["image"] do
                  %Plug.Upload{} = upload ->
                    case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                      {:ok, upload_result} ->
                        case ShotElixir.ActiveStorage.attach_image(
                               "Faction",
                               faction.id,
                               upload_result
                             ) do
                          {:ok, _attachment} ->
                            faction = Factions.get_faction(faction.id)

                            conn
                            |> put_status(:created)
                            |> put_view(ShotElixirWeb.Api.V2.FactionView)
                            |> render("show.json", faction: faction)

                          {:error, _changeset} ->
                            conn
                            |> put_status(:created)
                            |> put_view(ShotElixirWeb.Api.V2.FactionView)
                            |> render("show.json", faction: faction)
                        end

                      {:error, _reason} ->
                        conn
                        |> put_status(:created)
                        |> put_view(ShotElixirWeb.Api.V2.FactionView)
                        |> render("show.json", faction: faction)
                    end

                  _ ->
                    conn
                    |> put_status(:created)
                    |> put_view(ShotElixirWeb.Api.V2.FactionView)
                    |> render("show.json", faction: faction)
                end

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> put_view(ShotElixirWeb.Api.V2.FactionView)
                |> render("error.json", changeset: changeset)
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
                # Handle image upload if present
                case conn.params["image"] do
                  %Plug.Upload{} = upload ->
                    # Upload image to ImageKit
                    case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                      {:ok, upload_result} ->
                        # Attach image to faction via ActiveStorage
                        case ShotElixir.ActiveStorage.attach_image(
                               "Faction",
                               faction.id,
                               upload_result
                             ) do
                          {:ok, _attachment} ->
                            # Reload faction to get fresh data after image attachment
                            faction = Factions.get_faction(faction.id)
                            # Continue with faction update
                            case Factions.update_faction(faction, parsed_params) do
                              {:ok, faction} ->
                                conn
                                |> put_view(ShotElixirWeb.Api.V2.FactionView)
                                |> render("show.json", faction: faction)

                              {:error, changeset} ->
                                conn
                                |> put_status(:unprocessable_entity)
                                |> put_view(ShotElixirWeb.Api.V2.FactionView)
                                |> render("error.json", changeset: changeset)
                            end

                          {:error, changeset} ->
                            conn
                            |> put_status(:unprocessable_entity)
                            |> put_view(ShotElixirWeb.Api.V2.FactionView)
                            |> render("error.json", changeset: changeset)
                        end

                      {:error, reason} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
                    end

                  _ ->
                    # No image upload, just update faction
                    case Factions.update_faction(faction, parsed_params) do
                      {:ok, faction} ->
                        conn
                        |> put_view(ShotElixirWeb.Api.V2.FactionView)
                        |> render("show.json", faction: faction)

                      {:error, changeset} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> put_view(ShotElixirWeb.Api.V2.FactionView)
                        |> render("error.json", changeset: changeset)
                    end
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
              # Remove image from ActiveStorage
              case ShotElixir.ActiveStorage.delete_image("Faction", faction.id) do
                {:ok, _} ->
                  # Reload faction to get fresh data after image removal
                  updated_faction = Factions.get_faction(faction.id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.FactionView)
                  |> render("show.json", faction: updated_faction)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.FactionView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Faction not found"})
            end
        end
    end
  end

  # POST /api/v2/factions/:faction_id/duplicate
  def duplicate(conn, %{"faction_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user),
         %{} = faction <- Factions.get_faction(id),
         true <- faction.campaign_id == campaign_id,
         campaign <- Campaigns.get_campaign(campaign_id),
         true <- authorize_campaign_modification(campaign, current_user),
         {:ok, new_faction} <- Factions.duplicate_faction(faction) do
      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.FactionView)
      |> render("show.json", faction: new_faction)
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only campaign owners, admins, or gamemasters can duplicate factions"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.FactionView)
        |> render("error.json", changeset: changeset)
    end
  end

  # POST /api/v2/factions/:faction_id/sync
  def sync(conn, %{"faction_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Factions.get_faction(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      faction ->
        case Campaigns.get_campaign(faction.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Faction not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case NotionService.sync_faction(faction) do
                {:ok, :unlinked} ->
                  # Page was deleted in Notion, reload faction to get cleared notion_page_id
                  updated_faction = Factions.get_faction(id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.FactionView)
                  |> render("show.json", faction: updated_faction)

                {:ok, updated_faction} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.FactionView)
                  |> render("show.json", faction: updated_faction)

                {:error, {:notion_api_error, code, message}} ->
                  Logger.error("Notion API error syncing faction: #{code} - #{message}")

                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to sync to Notion: #{message}"})

                {:error, reason} ->
                  Logger.error("Failed to sync faction to Notion: #{inspect(reason)}")

                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to sync to Notion"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can sync factions"})
            end
        end
    end
  end

  # Private helper functions
  defp ensure_campaign(nil), do: {:error, :unauthorized}
  defp ensure_campaign(%{current_campaign_id: nil}), do: {:error, :no_campaign}
  defp ensure_campaign(%{current_campaign_id: campaign_id}), do: {:ok, campaign_id}

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
