defmodule ShotElixirWeb.Api.V2.VehicleJSON do
  # alias ShotElixir.Vehicles.Vehicle

  def index(%{vehicles: data}) when is_map(data) do
    # Handle paginated response with metadata
    vehicles_list = Map.get(data, :vehicles) || Map.get(data, "vehicles") || []

    %{
      vehicles: Enum.map(vehicles_list, &vehicle_json/1),
      meta: Map.get(data, :meta) || Map.get(data, "meta") || %{}
    }
  end

  def index(%{vehicles: vehicles}) when is_list(vehicles) do
    # Handle simple list response
    %{vehicles: Enum.map(vehicles, &vehicle_json/1)}
  end

  def show(%{vehicle: vehicle}) do
    vehicle_json(vehicle)
  end

  def archetypes(%{archetypes: archetypes}) do
    %{archetypes: archetypes}
  end

  def error(%{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  defp vehicle_json(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      action_values: vehicle.action_values,
      color: vehicle.color,
      impairments: vehicle.impairments,
      active: vehicle.active,
      image_url: vehicle.image_url,
      task: vehicle.task,
      summary: vehicle.summary,
      description: vehicle.description,
      user_id: vehicle.user_id,
      campaign_id: vehicle.campaign_id,
      faction_id: vehicle.faction_id,
      juncture_id: vehicle.juncture_id,
      created_at: vehicle.created_at,
      updated_at: vehicle.updated_at,
      entity_class: "Vehicle"
    }
  end
end
