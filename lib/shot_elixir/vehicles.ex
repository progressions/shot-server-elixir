defmodule ShotElixir.Vehicles do
  @moduledoc """
  The Vehicles context for managing vehicles in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Vehicles.Vehicle

  def list_vehicles(campaign_id) do
    query = from v in Vehicle,
      where: v.campaign_id == ^campaign_id and v.active == true,
      order_by: [asc: fragment("lower(?)", v.name)]

    Repo.all(query)
  end

  def get_vehicle!(id), do: Repo.get!(Vehicle, id)
  def get_vehicle(id), do: Repo.get(Vehicle, id)

  def create_vehicle(attrs \\ %{}) do
    %Vehicle{}
    |> Vehicle.changeset(attrs)
    |> Repo.insert()
  end

  def update_vehicle(%Vehicle{} = vehicle, attrs) do
    vehicle
    |> Vehicle.changeset(attrs)
    |> Repo.update()
  end

  def delete_vehicle(%Vehicle{} = vehicle) do
    vehicle
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def list_vehicle_archetypes do
    # This would normally come from a configuration or database
    # For now, return a simple list
    [
      %{id: "sports_car", name: "Sports Car", frame: 8, handling: 11},
      %{id: "motorcycle", name: "Motorcycle", frame: 6, handling: 12},
      %{id: "sedan", name: "Sedan", frame: 9, handling: 10},
      %{id: "suv", name: "SUV", frame: 10, handling: 9},
      %{id: "truck", name: "Truck", frame: 11, handling: 8},
      %{id: "helicopter", name: "Helicopter", frame: 10, handling: 10},
      %{id: "speedboat", name: "Speedboat", frame: 9, handling: 11}
    ]
  end
end