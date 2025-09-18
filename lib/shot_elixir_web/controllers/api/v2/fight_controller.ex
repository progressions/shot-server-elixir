defmodule ShotElixirWeb.Api.V2.FightController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/fights
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Get user's current campaign
    campaign_id = current_user.current_campaign_id

    if campaign_id do
      fights = Fights.list_fights(campaign_id)
      render(conn, :index, fights: fights)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/fights/:id
  def show(conn, %{"id" => id}) do
    fight = Fights.get_fight_with_shots(id)

    if fight do
      render(conn, :show, fight: fight)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Fight not found"})
    end
  end

  # POST /api/v2/fights
  def create(conn, %{"fight" => fight_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id if not provided
    fight_params = Map.put_new(fight_params, "campaign_id", current_user.current_campaign_id)

    with {:ok, campaign} <- get_campaign(fight_params["campaign_id"]),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, fight} <- Fights.create_fight(fight_params) do
      conn
      |> put_status(:created)
      |> render(:show, fight: fight)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can create fights"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/fights/:id
  def update(conn, %{"id" => id, "fight" => fight_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(id),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, fight} <- Fights.update_fight(fight, fight_params) do
      render(conn, :show, fight: fight)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update fights"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # DELETE /api/v2/fights/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(id),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, _fight} <- Fights.delete_fight(fight) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete fights"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete fight"})
    end
  end

  # PATCH /api/v2/fights/:id/touch
  def touch(conn, %{"fight_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(id),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, fight} <- Fights.touch_fight(fight) do
      render(conn, :show, fight: fight)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can touch fights"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to touch fight"})
    end
  end

  # PATCH /api/v2/fights/:id/end_fight
  def end_fight(conn, %{"fight_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(id),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, fight} <- Fights.end_fight(fight) do
      render(conn, :show, fight: fight)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can end fights"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to end fight"})
    end
  end

  # GET /api/v2/campaigns/:id/current_fight
  def current_fight(conn, %{"campaign_id" => campaign_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign} <- get_campaign(campaign_id),
         :ok <- authorize_member(current_user, campaign) do
      fights = Fights.list_fights(campaign_id)
      current_fight = List.first(fights)

      if current_fight do
        fight = Fights.get_fight_with_shots(current_fight.id)
        render(conn, :show, fight: fight)
      else
        conn
        |> put_status(:not_found)
        |> json(%{error: "No active fight found"})
      end
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to view this campaign"})
    end
  end

  # Private helper functions
  defp get_fight(id) do
    case Fights.get_fight(id) do
      nil -> {:error, :not_found}
      fight -> {:ok, fight}
    end
  end

  defp get_campaign(nil), do: {:error, :not_found}
  defp get_campaign(id) do
    case Campaigns.get_campaign(id) do
      nil -> {:error, :not_found}
      campaign -> {:ok, campaign}
    end
  end

  defp authorize_gamemaster(user, campaign) do
    if user.id == campaign.user_id || user.admin do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_member(user, campaign) do
    # Check if user is gamemaster or a member of the campaign
    if user.id == campaign.user_id ||
       user.admin ||
       Campaigns.is_member?(campaign.id, user.id) do
      :ok
    else
      {:error, :forbidden}
    end
  end
end