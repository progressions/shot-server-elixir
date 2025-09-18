defmodule ShotElixirWeb.Api.V2.JunctureController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Junctures
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/junctures
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      junctures = Junctures.list_junctures(current_user.current_campaign_id)
      render(conn, :index, junctures: junctures)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/junctures/:id
  def show(conn, %{"id" => id}) do
    juncture = Junctures.get_juncture(id)

    if juncture do
      render(conn, :show, juncture: juncture)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Juncture not found"})
    end
  end

  # POST /api/v2/junctures
  def create(conn, %{"juncture" => juncture_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id if not provided
    juncture_params = Map.put_new(juncture_params, "campaign_id", current_user.current_campaign_id)

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
  end

  # PATCH/PUT /api/v2/junctures/:id
  def update(conn, %{"id" => id, "juncture" => juncture_params}) do
    juncture = Junctures.get_juncture(id)

    cond do
      juncture == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Juncture not found"})

      true ->
        case Junctures.update_juncture(juncture, juncture_params) do
          {:ok, juncture} ->
            render(conn, :show, juncture: juncture)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/junctures/:id
  def delete(conn, %{"id" => id}) do
    juncture = Junctures.get_juncture(id)

    cond do
      juncture == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Juncture not found"})

      true ->
        case Junctures.delete_juncture(juncture) do
          {:ok, _juncture} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete juncture"})
        end
    end
  end
end