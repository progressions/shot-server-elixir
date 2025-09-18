defmodule ShotElixirWeb.Api.V2.FactionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Factions
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/factions
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      factions = Factions.list_factions(current_user.current_campaign_id)
      render(conn, :index, factions: factions)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/factions/:id
  def show(conn, %{"id" => id}) do
    faction = Factions.get_faction(id)

    if faction do
      render(conn, :show, faction: faction)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Faction not found"})
    end
  end

  # POST /api/v2/factions
  def create(conn, %{"faction" => faction_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id if not provided
    faction_params = Map.put_new(faction_params, "campaign_id", current_user.current_campaign_id)

    case Factions.create_faction(faction_params) do
      {:ok, faction} ->
        conn
        |> put_status(:created)
        |> render(:show, faction: faction)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/factions/:id
  def update(conn, %{"id" => id, "faction" => faction_params}) do
    faction = Factions.get_faction(id)

    cond do
      faction == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      true ->
        case Factions.update_faction(faction, faction_params) do
          {:ok, faction} ->
            render(conn, :show, faction: faction)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/factions/:id
  def delete(conn, %{"id" => id}) do
    faction = Factions.get_faction(id)

    cond do
      faction == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Faction not found"})

      true ->
        case Factions.delete_faction(faction) do
          {:ok, _faction} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete faction"})
        end
    end
  end
end
