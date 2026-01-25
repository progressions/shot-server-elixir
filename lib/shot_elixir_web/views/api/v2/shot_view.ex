defmodule ShotElixirWeb.Api.V2.ShotView do
  def render("set_location.json", %{shot: shot, created: created}) do
    %{
      shot: render_shot(shot),
      created: created
    }
  end

  defp render_shot(shot) do
    %{
      id: shot.id,
      shot: shot.shot,
      position: shot.position,
      count: shot.count,
      color: shot.color,
      impairments: shot.impairments,
      location: shot.location,
      location_id: shot.location_id,
      location_data: render_location(shot.location_ref),
      was_rammed_or_damaged: shot.was_rammed_or_damaged,
      fight_id: shot.fight_id,
      character_id: shot.character_id,
      vehicle_id: shot.vehicle_id,
      driver_id: shot.driver_id,
      driving_id: shot.driving_id,
      character: render_character_if_loaded(shot),
      vehicle: render_vehicle_if_loaded(shot)
    }
  end

  defp render_location(nil), do: nil

  defp render_location(%Ecto.Association.NotLoaded{}), do: nil

  defp render_location(location) do
    %{
      id: location.id,
      name: location.name,
      color: location.color,
      description: location.description
    }
  end

  defp render_character_if_loaded(shot) do
    case shot.character do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      character -> %{id: character.id, name: character.name}
    end
  end

  defp render_vehicle_if_loaded(shot) do
    case shot.vehicle do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      vehicle -> %{id: vehicle.id, name: vehicle.name}
    end
  end
end
