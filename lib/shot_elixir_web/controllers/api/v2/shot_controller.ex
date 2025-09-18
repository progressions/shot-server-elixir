defmodule ShotElixirWeb.Api.V2.ShotController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # POST /api/v2/fights/:fight_id/shots
  def create(conn, %{"fight_id" => fight_id, "shot" => shot_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    shot_params = Map.put(shot_params, "fight_id", fight_id)

    with {:ok, fight} <- get_fight(fight_id),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, shot} <- Fights.create_shot(shot_params) do
      conn
      |> put_status(:created)
      |> render(:show, shot: shot)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can create shots"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/fights/:fight_id/shots/:id
  def update(conn, %{"fight_id" => fight_id, "id" => id, "shot" => shot_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, shot} <- get_shot(id),
         {:ok, fight} <- get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, shot} <- Fights.update_shot(shot, shot_params) do
      render(conn, :show, shot: shot)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update shots"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # DELETE /api/v2/fights/:fight_id/shots/:id
  def delete(conn, %{"fight_id" => fight_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, shot} <- get_shot(id),
         {:ok, fight} <- get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, _shot} <- Fights.delete_shot(shot) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete shots"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete shot"})
    end
  end

  # PATCH /api/v2/fights/:fight_id/shots/:id/act
  def act(conn, %{"fight_id" => fight_id, "shot_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, shot} <- get_shot(id),
         {:ok, fight} <- get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, shot} <- Fights.act_on_shot(shot) do
      render(conn, :show, shot: shot)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can act on shots"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to act on shot"})
    end
  end

  # POST /api/v2/fights/:fight_id/shots/:id/assign_driver
  def assign_driver(conn, %{"fight_id" => fight_id, "shot_id" => shot_id, "driver" => driver_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, shot} <- get_shot(shot_id),
         {:ok, fight} <- get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         {:ok, _driver} <- create_driver(shot_id, driver_params) do
      shot = Fights.get_shot_with_drivers(shot_id)
      render(conn, :show, shot: shot)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can assign drivers"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # DELETE /api/v2/fights/:fight_id/shots/:id/remove_driver
  def remove_driver(conn, %{"fight_id" => fight_id, "shot_id" => shot_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, shot} <- get_shot(shot_id),
         {:ok, fight} <- get_fight(fight_id),
         :ok <- validate_shot_belongs_to_fight(shot, fight),
         {:ok, campaign} <- get_campaign(fight.campaign_id),
         :ok <- authorize_gamemaster(current_user, campaign),
         :ok <- remove_all_drivers(shot_id) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Shot or fight not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can remove drivers"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to remove driver"})
    end
  end

  # Private helper functions
  defp get_fight(id) do
    case Fights.get_fight(id) do
      nil -> {:error, :not_found}
      fight -> {:ok, fight}
    end
  end

  defp get_shot(id) do
    case Fights.get_shot(id) do
      nil -> {:error, :not_found}
      shot -> {:ok, shot}
    end
  end

  defp get_campaign(id) do
    case Campaigns.get_campaign(id) do
      nil -> {:error, :not_found}
      campaign -> {:ok, campaign}
    end
  end

  defp validate_shot_belongs_to_fight(shot, fight) do
    if shot.fight_id == fight.id do
      :ok
    else
      {:error, :mismatch}
    end
  end

  defp authorize_gamemaster(user, campaign) do
    if user.id == campaign.user_id || user.admin do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp create_driver(shot_id, driver_params) do
    driver_params = Map.put(driver_params, "shot_id", shot_id)
    Fights.create_shot_driver(driver_params)
  end

  defp remove_all_drivers(shot_id) do
    Fights.remove_shot_drivers(shot_id)
  end
end