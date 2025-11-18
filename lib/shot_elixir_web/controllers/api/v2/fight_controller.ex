defmodule ShotElixirWeb.Api.V2.FightController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Fights.Fight
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/fights
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Get current campaign from user or params
    campaign_id = current_user.current_campaign_id || params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    else
      fights_data = Fights.list_campaign_fights(campaign_id, params, current_user)

      conn
      |> put_view(ShotElixirWeb.Api.V2.FightView)
      |> render("index.json", fights: fights_data.fights, meta: fights_data.meta)
    end
  end

  # GET /api/v2/fights/:id
  def show(conn, %{"id" => id}) do
    fight = Fights.get_fight_with_shots(id)

    if fight do
      conn
      |> put_view(ShotElixirWeb.Api.V2.FightView)
      |> render("show.json", fight: fight)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Fight not found"})
    end
  end

  # POST /api/v2/fights
  def create(conn, %{"fight" => fight_params}) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id || fight_params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    else
      campaign = Campaigns.get_campaign(campaign_id)

      # Only gamemaster can create fights
      unless campaign.user_id == current_user.id || current_user.gamemaster do
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can create fights"})
      else
        # Handle JSON string parameters (Rails compatibility)
        parsed_params = parse_json_params(fight_params)

        params =
          parsed_params
          |> Map.put("campaign_id", campaign_id)

        case Fights.create_fight(params) do
          {:ok, fight} ->
            conn
            |> put_status(:created)
            |> put_view(ShotElixirWeb.Api.V2.FightView)
            |> render("show.json", fight: fight)

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(ShotElixirWeb.Api.V2.FightView)
            |> render("error.json", changeset: changeset)
        end
      end
    end
  end

  # PATCH/PUT /api/v2/fights/:id
  def update(conn, %{"id" => id, "fight" => fight_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Fight{} = fight <- Fights.get_fight(id),
         :ok <- authorize_fight_edit(fight, current_user) do
      # Handle image upload if present
      case conn.params["image"] do
        %Plug.Upload{} = upload ->
          # Upload image to ImageKit
          case ShotElixir.Services.ImagekitService.upload_plug(upload) do
            {:ok, upload_result} ->
              # Attach image to fight via ActiveStorage
              case ShotElixir.ActiveStorage.attach_image("Fight", fight.id, upload_result) do
                {:ok, _attachment} ->
                  # Reload fight to get fresh data after image attachment
                  fight = Fights.get_fight(fight.id)
                  # Continue with fight update
                  case Fights.update_fight(fight, parse_json_params(fight_params)) do
                    {:ok, updated_fight} ->
                      conn
                      |> put_view(ShotElixirWeb.Api.V2.FightView)
                      |> render("show.json", fight: updated_fight)

                    {:error, changeset} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> put_view(ShotElixirWeb.Api.V2.FightView)
                      |> render("error.json", changeset: changeset)
                  end

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.FightView)
                  |> render("error.json", changeset: changeset)
              end

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
          end

        _ ->
          # No image upload, just update fight
          case Fights.update_fight(fight, parse_json_params(fight_params)) do
            {:ok, updated_fight} ->
              conn
              |> put_view(ShotElixirWeb.Api.V2.FightView)
              |> render("show.json", fight: updated_fight)

            {:error, %Ecto.Changeset{} = changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> put_view(ShotElixirWeb.Api.V2.FightView)
              |> render("error.json", changeset: changeset)
          end
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update fights"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})
    end
  end

  # DELETE /api/v2/fights/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Fight{} = fight <- Fights.get_fight(id),
         :ok <- authorize_fight_edit(fight, current_user),
         {:ok, _} <- Fights.delete_fight(fight) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete fights"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # PATCH /api/v2/fights/:id/touch
  def touch(conn, %{"fight_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Fight{} = fight <- Fights.get_fight(id),
         :ok <- authorize_fight_edit(fight, current_user),
         {:ok, fight} <- Fights.touch_fight(fight) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.FightView)
      |> render("show.json", fight: fight)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can touch fights"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # PATCH /api/v2/fights/:id/end_fight
  def end_fight(conn, %{"fight_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Fight{} = fight <- Fights.get_fight(id),
         :ok <- authorize_fight_edit(fight, current_user),
         {:ok, fight} <- Fights.end_fight(fight) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.FightView)
      |> render("show.json", fight: fight)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can end fights"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Custom endpoints
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Fight{} = fight <- Fights.get_fight(id),
         :ok <- authorize_fight_edit(fight, current_user) do
      # Remove image from ActiveStorage
      case ShotElixir.ActiveStorage.delete_image("Fight", fight.id) do
        {:ok, _} ->
          # Reload fight to get fresh data after image removal
          updated_fight = Fights.get_fight(fight.id)
          conn
          |> put_view(ShotElixirWeb.Api.V2.FightView)
          |> render("show.json", fight: updated_fight)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.FightView)
          |> render("error.json", changeset: changeset)
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
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

  # Handle JSON string parameters for Rails compatibility
  defp parse_json_params(params) when is_binary(params) do
    case Jason.decode(params) do
      {:ok, decoded} -> decoded
      {:error, _} -> params
    end
  end

  defp parse_json_params(params), do: params
end
