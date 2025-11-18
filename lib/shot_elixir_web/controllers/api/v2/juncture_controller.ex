defmodule ShotElixirWeb.Api.V2.JunctureController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Junctures
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  plug :put_view, ShotElixirWeb.Api.V2.JunctureView

  # GET /api/v2/junctures
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
              Junctures.list_campaign_junctures(
                current_user.current_campaign_id,
                params,
                current_user
              )

            render(conn, :index, junctures: result.junctures, meta: result.meta)
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

  # GET /api/v2/junctures/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Junctures.get_juncture_with_preloads(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Juncture not found"})

      juncture ->
        # Check campaign access
        case Campaigns.get_campaign(juncture.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Juncture not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              render(conn, :show, juncture: juncture)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Juncture not found"})
            end
        end
    end
  end

  # POST /api/v2/junctures
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"juncture" => juncture_data} when is_binary(juncture_data) ->
          case Jason.decode(juncture_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid juncture data format"})
              |> halt()
          end

        %{"juncture" => juncture_data} when is_map(juncture_data) ->
          juncture_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Juncture parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # Add campaign_id from current campaign
      juncture_params = Map.put(parsed_params, "campaign_id", current_user.current_campaign_id)

      # Verify campaign access
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No active campaign selected"})

        campaign ->
          if authorize_campaign_modification(campaign, current_user) do
            case Junctures.create_juncture(juncture_params) do
              {:ok, juncture} ->
                conn
                |> put_status(:created)
                |> render(:show, juncture: juncture)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> render(:error, changeset: changeset)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only gamemaster can create junctures"})
          end
      end
    end
  end

  # PATCH/PUT /api/v2/junctures/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Junctures.get_juncture(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Juncture not found"})

      juncture ->
        # Check campaign access
        case Campaigns.get_campaign(juncture.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Juncture not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Handle JSON string parsing like Rails
              parsed_params =
                case params do
                  %{"juncture" => juncture_data} when is_binary(juncture_data) ->
                    case Jason.decode(juncture_data) do
                      {:ok, decoded} ->
                        decoded

                      {:error, _} ->
                        conn
                        |> put_status(:bad_request)
                        |> json(%{error: "Invalid juncture data format"})
                        |> halt()
                    end

                  %{"juncture" => juncture_data} when is_map(juncture_data) ->
                    juncture_data

                  _ ->
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Juncture parameters required"})
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
                        # Attach image to juncture via ActiveStorage
                        case ShotElixir.ActiveStorage.attach_image("Juncture", juncture.id, upload_result) do
                          {:ok, _attachment} ->
                            # Reload juncture to get fresh data after image attachment
                            juncture = Junctures.get_juncture_with_preloads(juncture.id)
                            # Continue with juncture update
                            case Junctures.update_juncture(juncture, parsed_params) do
                              {:ok, updated_juncture} ->
                                render(conn, :show, juncture: updated_juncture)

                              {:error, changeset} ->
                                conn
                                |> put_status(:unprocessable_entity)
                                |> render(:error, changeset: changeset)
                            end

                          {:error, changeset} ->
                            conn
                            |> put_status(:unprocessable_entity)
                            |> render(:error, changeset: changeset)
                        end

                      {:error, reason} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
                    end

                  _ ->
                    # No image upload, just update juncture
                    case Junctures.update_juncture(juncture, parsed_params) do
                      {:ok, juncture} ->
                        render(conn, :show, juncture: juncture)

                      {:error, changeset} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> render(:error, changeset: changeset)
                    end
                end
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Juncture not found"})
            end
        end
    end
  end

  # DELETE /api/v2/junctures/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Junctures.get_juncture(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Juncture not found"})

      juncture ->
        # Check campaign access
        case Campaigns.get_campaign(juncture.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Juncture not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Junctures.delete_juncture(juncture) do
                {:ok, _juncture} ->
                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete juncture"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Juncture not found"})
            end
        end
    end
  end

  # DELETE /api/v2/junctures/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Junctures.get_juncture(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Juncture not found"})

      juncture ->
        # Check campaign access
        case Campaigns.get_campaign(juncture.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Juncture not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Remove image from ActiveStorage
              case ShotElixir.ActiveStorage.delete_image("Juncture", juncture.id) do
                {:ok, _} ->
                  # Reload juncture to get fresh data after image removal
                  updated_juncture = Junctures.get_juncture_with_preloads(juncture.id)
                  render(conn, :show, juncture: updated_juncture)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> render(:error, changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Juncture not found"})
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
