defmodule ShotElixirWeb.Api.V2.SchticksController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Schticks
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/schticks
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      schticks = Schticks.list_schticks(current_user.current_campaign_id, params)
      render(conn, :index, schticks: schticks)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/schticks/:id
  def show(conn, %{"id" => id}) do
    schtick = Schticks.get_schtick(id)

    if schtick do
      render(conn, :show, schtick: schtick)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Schtick not found"})
    end
  end

  # POST /api/v2/schticks
  def create(conn, %{"schtick" => schtick_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id if not provided
    schtick_params = Map.put_new(schtick_params, "campaign_id", current_user.current_campaign_id)

    case Schticks.create_schtick(schtick_params) do
      {:ok, schtick} ->
        conn
        |> put_status(:created)
        |> render(:show, schtick: schtick)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/schticks/:id
  def update(conn, %{"id" => id, "schtick" => schtick_params}) do
    schtick = Schticks.get_schtick(id)

    cond do
      schtick == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Schtick not found"})

      true ->
        case Schticks.update_schtick(schtick, schtick_params) do
          {:ok, schtick} ->
            render(conn, :show, schtick: schtick)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/schticks/:id
  def delete(conn, %{"id" => id}) do
    schtick = Schticks.get_schtick(id)

    cond do
      schtick == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Schtick not found"})

      true ->
        case Schticks.delete_schtick(schtick) do
          {:ok, _schtick} ->
            send_resp(conn, :no_content, "")

          {:error, :has_dependents} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Cannot delete schtick with dependent schticks"})

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete schtick"})
        end
    end
  end
end