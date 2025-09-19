defmodule ShotElixirWeb.Api.V2.VehicleController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Vehicles
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/vehicles
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Get current campaign from user or params
    campaign_id = current_user.current_campaign_id || params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    else
      vehicles_data = Vehicles.list_campaign_vehicles(campaign_id, params, current_user)

      conn
      |> put_view(ShotElixirWeb.Api.V2.VehicleView)
      |> render("index.json", vehicles: vehicles_data)
    end
  end

  # GET /api/v2/vehicles/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)
    vehicle = Vehicles.get_vehicle_with_preloads(id)

    with %Vehicle{} = vehicle <- vehicle,
         :ok <- authorize_vehicle_access(vehicle, current_user) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.VehicleView)
      |> render("show.json", vehicle: vehicle)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to view this vehicle"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})
    end
  end

  # POST /api/v2/vehicles
  def create(conn, %{"vehicle" => vehicle_params}) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id || vehicle_params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    else
      campaign = Campaigns.get_campaign(campaign_id)

      cond do
        !campaign ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign.user_id != current_user.id && !current_user.gamemaster && !Campaigns.is_member?(campaign.id, current_user.id) ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Only gamemaster can create vehicles"})

        true ->
          # Handle JSON string parameters (Rails compatibility)
          parsed_params = parse_json_params(vehicle_params)

          params =
            parsed_params
            |> Map.put("campaign_id", campaign_id)
            |> Map.put("user_id", current_user.id)

          case Vehicles.create_vehicle(params) do
            {:ok, vehicle} ->
              conn
              |> put_status(:created)
              |> put_view(ShotElixirWeb.Api.V2.VehicleView)
              |> render("show.json", vehicle: vehicle)

            {:error, %Ecto.Changeset{} = changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> put_view(ShotElixirWeb.Api.V2.VehicleView)
              |> render("error.json", changeset: changeset)
          end
      end
    end
  end

  # PATCH/PUT /api/v2/vehicles/:id
  def update(conn, %{"id" => id, "vehicle" => vehicle_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Vehicle{} = vehicle <- Vehicles.get_vehicle(id),
         :ok <- authorize_vehicle_edit(vehicle, current_user) do

      # Handle image upload if present
      updated_vehicle =
        case Map.get(vehicle_params, "image") do
          %Plug.Upload{} = upload ->
            case Vehicles.update_vehicle(vehicle, %{"image" => upload}) do
              {:ok, v} -> v
              _ -> vehicle
            end
          _ ->
            vehicle
        end

      # Continue with normal update
      case Vehicles.update_vehicle(updated_vehicle, parse_json_params(vehicle_params)) do
        {:ok, final_vehicle} ->
          conn
          |> put_view(ShotElixirWeb.Api.V2.VehicleView)
          |> render("show.json", vehicle: final_vehicle)

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.VehicleView)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update vehicles"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.VehicleView)
        |> render("error.json", changeset: changeset)
    end
  end

  # DELETE /api/v2/vehicles/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Vehicle{} = vehicle <- Vehicles.get_vehicle(id),
         :ok <- authorize_vehicle_edit(vehicle, current_user),
         {:ok, _} <- Vehicles.delete_vehicle(vehicle) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete vehicles"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # GET /api/v2/vehicles/archetypes
  def archetypes(conn, _params) do
    archetypes = Vehicles.list_vehicle_archetypes()

    json(conn, %{archetypes: archetypes})
  end

  # DELETE /api/v2/vehicles/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Vehicle{} = vehicle <- Vehicles.get_vehicle(id),
         :ok <- authorize_vehicle_edit(vehicle, current_user) do
      # TODO: Implement image removal logic
      conn
      |> put_view(ShotElixirWeb.Api.V2.VehicleView)
      |> render("show.json", vehicle: vehicle)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # PATCH /api/v2/vehicles/:id/update_chase_state
  def update_chase_state(conn, %{"id" => id, "chase_state" => chase_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Vehicle{} = vehicle <- Vehicles.get_vehicle(id),
         :ok <- authorize_vehicle_edit(vehicle, current_user),
         {:ok, updated_vehicle} <- Vehicles.update_chase_state(vehicle, chase_params) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.VehicleView)
      |> render("show.json", vehicle: updated_vehicle)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update vehicle chase state"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Vehicle not found"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.VehicleView)
        |> render("error.json", changeset: changeset)

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  # Authorization helpers
  defp authorize_vehicle_access(vehicle, user) do
    campaign_id = vehicle.campaign_id
    campaigns = Campaigns.get_user_campaigns(user.id)

    if Enum.any?(campaigns, fn c -> c.id == campaign_id end) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_vehicle_edit(vehicle, user) do
    campaign = Campaigns.get_campaign(vehicle.campaign_id)

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
