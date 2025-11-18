defmodule ShotElixirWeb.Api.V2.ChaseRelationshipController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Chases
  alias ShotElixir.Chases.ChaseRelationship
  alias ShotElixir.Guardian
  alias ShotElixirWeb.Api.V2.VehicleView

  action_fallback ShotElixirWeb.FallbackController

  def index(conn, params) do
    with {:ok, {campaign_id, _user}} <- current_campaign(conn) do
      relationships = Chases.list_relationships(campaign_id, params)

      conn
      |> json(%{
        "chase_relationships" => Enum.map(relationships, &serialize_basic/1)
      })
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      {:error, :unauthenticated} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, {campaign_id, _user}} <- current_campaign(conn),
         %ChaseRelationship{} = relationship <- Chases.get_relationship(id, campaign_id) do
      json(conn, %{"chase_relationship" => serialize_detail(relationship)})
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      {:error, :unauthenticated} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Chase relationship not found"})
    end
  end

  def create(conn, %{"chase_relationship" => attrs}) do
    with {:ok, {campaign_id, user}} <- current_campaign(conn),
         :ok <- require_gamemaster(user),
         {:ok, %ChaseRelationship{} = relationship} <-
           Chases.create_relationship(attrs, campaign_id),
         %ChaseRelationship{} = reloaded <- Chases.get_relationship(relationship.id, campaign_id) do
      conn
      |> put_status(:created)
      |> json(%{"chase_relationship" => serialize_detail(reloaded)})
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      {:error, :unauthenticated} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemasters can perform this action"})

      {:error, :invalid_resource} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid resources for this campaign"})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id, "chase_relationship" => attrs}) do
    with {:ok, {campaign_id, user}} <- current_campaign(conn),
         :ok <- require_gamemaster(user),
         %ChaseRelationship{} = relationship <- Chases.get_relationship(id, campaign_id),
         {:ok, %ChaseRelationship{} = updated} <- Chases.update_relationship(relationship, attrs),
         %ChaseRelationship{} = reloaded <- Chases.get_relationship(updated.id, campaign_id) do
      json(conn, %{"chase_relationship" => serialize_detail(reloaded)})
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      {:error, :unauthenticated} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemasters can perform this action"})

      {:error, :invalid_resource} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid resources for this campaign"})

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Chase relationship not found"})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, {campaign_id, user}} <- current_campaign(conn),
         :ok <- require_gamemaster(user),
         %ChaseRelationship{} = relationship <- Chases.get_relationship(id, campaign_id),
         {:ok, _} <- Chases.deactivate_relationship(relationship) do
      send_resp(conn, :no_content, "")
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      {:error, :unauthenticated} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemasters can perform this action"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Chase relationship not found"})
    end
  end

  defp current_campaign(conn) do
    case Guardian.Plug.current_resource(conn) do
      nil -> {:error, :unauthenticated}
      user when is_nil(user.current_campaign_id) -> {:error, :no_campaign}
      user -> {:ok, {user.current_campaign_id, user}}
    end
  end

  defp require_gamemaster(user) do
    if user.admin || user.gamemaster do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp serialize_basic(%ChaseRelationship{} = relationship) do
    %{
      id: relationship.id,
      pursuer_id: relationship.pursuer_id,
      evader_id: relationship.evader_id,
      fight_id: relationship.fight_id,
      position: relationship.position,
      active: relationship.active,
      created_at: relationship.created_at,
      updated_at: relationship.updated_at
    }
  end

  defp serialize_detail(%ChaseRelationship{} = relationship) do
    base = serialize_basic(relationship)

    base
    |> Map.put(:pursuer, serialize_vehicle(relationship.pursuer))
    |> Map.put(:evader, serialize_vehicle(relationship.evader))
  end

  defp serialize_vehicle(nil), do: nil

  defp serialize_vehicle(vehicle) do
    VehicleView.render("show.json", %{vehicle: vehicle})[:vehicle]
  end
end
