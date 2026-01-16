defmodule ShotElixirWeb.Api.V2.AdventureController do
  use ShotElixirWeb, :controller

  require Logger

  alias ShotElixir.Adventures
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Services.NotionService
  alias ShotElixirWeb.Api.V2.SyncFromNotion

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/adventures
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            result =
              Adventures.list_campaign_adventures(
                current_user.current_campaign_id,
                params,
                current_user
              )

            conn
            |> put_view(ShotElixirWeb.Api.V2.AdventureView)
            |> render("index.json",
              adventures: result.adventures,
              meta: result.meta
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

  # GET /api/v2/adventures/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              conn
              |> put_view(ShotElixirWeb.Api.V2.AdventureView)
              |> render("show.json", adventure: adventure)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # POST /api/v2/adventures
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    parsed_params =
      case params do
        %{"adventure" => adventure_data} when is_binary(adventure_data) ->
          case Jason.decode(adventure_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid adventure data format"})
              |> halt()
          end

        %{"adventure" => adventure_data} when is_map(adventure_data) ->
          adventure_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Adventure parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      if is_nil(current_user.current_campaign_id) do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})
      else
        adventure_params =
          parsed_params
          |> Map.put("campaign_id", current_user.current_campaign_id)
          |> Map.put("user_id", current_user.id)

        case Campaigns.get_campaign(current_user.current_campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Campaign not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.create_adventure(adventure_params) do
                {:ok, adventure} ->
                  adventure = maybe_handle_image_upload(conn, adventure)

                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: adventure)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can create adventures"})
            end
        end
      end
    end
  end

  # PATCH/PUT /api/v2/adventures/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              parsed_params =
                case params do
                  %{"adventure" => adventure_data} when is_binary(adventure_data) ->
                    case Jason.decode(adventure_data) do
                      {:ok, decoded} ->
                        decoded

                      {:error, _} ->
                        conn
                        |> put_status(:bad_request)
                        |> json(%{error: "Invalid adventure data format"})
                        |> halt()
                    end

                  %{"adventure" => adventure_data} when is_map(adventure_data) ->
                    adventure_data

                  _ ->
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Adventure parameters required"})
                    |> halt()
                end

              if conn.halted do
                conn
              else
                adventure = maybe_handle_image_upload(conn, adventure)

                case Adventures.update_adventure(adventure, parsed_params) do
                  {:ok, updated_adventure} ->
                    conn
                    |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                    |> render("show.json", adventure: updated_adventure)

                  {:error, changeset} ->
                    conn
                    |> put_status(:unprocessable_entity)
                    |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                    |> render("error.json", changeset: changeset)
                end
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # DELETE /api/v2/adventures/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.delete_adventure(adventure) do
                {:ok, _deleted_adventure} ->
                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete adventure"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # DELETE /api/v2/adventures/:id/image
  def remove_image(conn, %{"adventure_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case ShotElixir.ActiveStorage.delete_image("Adventure", adventure.id) do
                {:ok, _} ->
                  updated_adventure = Adventures.get_adventure(adventure.id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # POST /api/v2/adventures/:id/duplicate
  def duplicate(conn, %{"adventure_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user),
         %{} = adventure <- Adventures.get_adventure(id),
         true <- adventure.campaign_id == campaign_id,
         campaign <- Campaigns.get_campaign(campaign_id),
         true <- authorize_campaign_modification(campaign, current_user),
         {:ok, new_adventure} <- Adventures.duplicate_adventure(adventure) do
      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.AdventureView)
      |> render("show.json", adventure: new_adventure)
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only campaign owners, admins, or gamemasters can duplicate adventures"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.AdventureView)
        |> render("error.json", changeset: changeset)
    end
  end

  # POST /api/v2/adventures/:id/characters
  def add_character(conn, %{"adventure_id" => adventure_id, "character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(adventure_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.add_character(adventure_id, character_id) do
                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # DELETE /api/v2/adventures/:id/characters/:character_id
  def remove_character(conn, %{"adventure_id" => adventure_id, "character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(adventure_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.remove_character(adventure_id, character_id) do
                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, :not_found} ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Character not in adventure"})

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to remove character"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # POST /api/v2/adventures/:id/villains
  def add_villain(conn, %{"adventure_id" => adventure_id, "character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(adventure_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.add_villain(adventure_id, character_id) do
                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # DELETE /api/v2/adventures/:id/villains/:character_id
  def remove_villain(conn, %{"adventure_id" => adventure_id, "character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(adventure_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.remove_villain(adventure_id, character_id) do
                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, :not_found} ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Villain not in adventure"})

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to remove villain"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # POST /api/v2/adventures/:id/fights
  def add_fight(conn, %{"adventure_id" => adventure_id, "fight_id" => fight_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(adventure_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.add_fight(adventure_id, fight_id) do
                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # DELETE /api/v2/adventures/:id/fights/:fight_id
  def remove_fight(conn, %{"adventure_id" => adventure_id, "fight_id" => fight_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(adventure_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Adventures.remove_fight(adventure_id, fight_id) do
                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, :not_found} ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Fight not in adventure"})

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to remove fight"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Adventure not found"})
            end
        end
    end
  end

  # POST /api/v2/adventures/:id/sync
  def sync(conn, %{"adventure_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case NotionService.sync_adventure(adventure) do
                {:ok, :unlinked} ->
                  # Page was deleted in Notion, reload adventure to get cleared notion_page_id
                  updated_adventure = Adventures.get_adventure(id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:ok, updated_adventure} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.AdventureView)
                  |> render("show.json", adventure: updated_adventure)

                {:error, :no_database_configured} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "No Notion database configured for adventures"})

                {:error, reason} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to sync adventure to Notion: #{inspect(reason)}"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{
                error: "Only campaign owners, admins, or gamemasters can sync adventures"
              })
            end
        end
    end
  end

  # POST /api/v2/adventures/:id/sync_from_notion
  def sync_from_notion(conn, %{"adventure_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Adventures.get_adventure(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      adventure ->
        case Campaigns.get_campaign(adventure.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Adventure not found"})

          campaign ->
            SyncFromNotion.sync(conn, current_user, adventure, campaign,
              assign_key: :adventure,
              authorize: &authorize_campaign_modification/2,
              forbidden_error: "Only campaign owners, admins, or gamemasters can sync adventures",
              no_page_error: "Adventure has no Notion page linked",
              require_page: &require_notion_page_linked/1,
              update: &NotionService.update_adventure_from_notion/2,
              view: ShotElixirWeb.Api.V2.AdventureView
            )
        end
    end
  end

  # Helper functions

  defp ensure_campaign(user) do
    if user.current_campaign_id do
      {:ok, user.current_campaign_id}
    else
      {:error, :no_campaign}
    end
  end

  defp maybe_handle_image_upload(conn, adventure) do
    case conn.params["image"] do
      %Plug.Upload{} = upload ->
        case ShotElixir.Services.ImagekitService.upload_plug(upload) do
          {:ok, upload_result} ->
            case ShotElixir.ActiveStorage.attach_image("Adventure", adventure.id, upload_result) do
              {:ok, _attachment} ->
                Adventures.get_adventure(adventure.id)

              {:error, _changeset} ->
                adventure
            end

          {:error, _reason} ->
            adventure
        end

      _ ->
        adventure
    end
  end

  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id ||
      user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
      Campaigns.is_member?(campaign.id, user.id)
  end

  defp authorize_campaign_modification(campaign, user) do
    campaign.user_id == user.id ||
      user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id))
  end

  defp require_notion_page_linked(%Adventures.Adventure{notion_page_id: nil}),
    do: {:error, :no_page}

  defp require_notion_page_linked(%Adventures.Adventure{}), do: :ok
end
