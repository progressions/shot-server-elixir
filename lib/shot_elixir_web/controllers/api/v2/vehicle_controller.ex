defmodule ShotElixirWeb.Api.V2.VehicleController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Vehicles
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/vehicles
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      vehicles = Vehicles.list_vehicles(current_user.current_campaign_id)
      render(conn, :index, vehicles: vehicles)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/vehicles/archetypes
  def archetypes(conn, _params) do
    archetypes = Vehicles.list_vehicle_archetypes()
    render(conn, :archetypes, archetypes: archetypes)
  end

  # GET /api/v2/vehicles/:id
  def show(conn, %{"id" => id}) do
    vehicle = Vehicles.get_vehicle(id)

    if vehicle do
      render(conn, :show, vehicle: vehicle)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Vehicle not found"})
    end
  end

  # POST /api/v2/vehicles
  def create(conn, %{"vehicle" => vehicle_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id and user_id if not provided
    vehicle_params = vehicle_params
      |> Map.put_new("campaign_id", current_user.current_campaign_id)
      |> Map.put_new("user_id", current_user.id)

    case Vehicles.create_vehicle(vehicle_params) do
      {:ok, vehicle} ->
        conn
        |> put_status(:created)
        |> render(:show, vehicle: vehicle)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/vehicles/:id
  def update(conn, %{"id" => id, "vehicle" => vehicle_params}) do
    vehicle = Vehicles.get_vehicle(id)

    cond do
      vehicle == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      true ->
        case Vehicles.update_vehicle(vehicle, vehicle_params) do
          {:ok, vehicle} ->
            render(conn, :show, vehicle: vehicle)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/vehicles/:id
  def delete(conn, %{"id" => id}) do
    vehicle = Vehicles.get_vehicle(id)

    cond do
      vehicle == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      true ->
        case Vehicles.delete_vehicle(vehicle) do
          {:ok, _vehicle} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete vehicle"})
        end
    end
  end
end