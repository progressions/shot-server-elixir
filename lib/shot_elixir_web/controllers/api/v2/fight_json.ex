defmodule ShotElixirWeb.Api.V2.FightJSON do
  alias ShotElixir.Fights.{Fight, Shot}

  def index(%{fights: fights}) do
    %{fights: Enum.map(fights, &fight_json/1)}
  end

  def show(%{fight: fight}) do
    %{fight: fight_json_with_shots(fight)}
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

  defp fight_json(fight) do
    %{
      id: fight.id,
      name: fight.name,
      active: fight.active,
      sequence: fight.sequence,
      archived: fight.archived,
      description: fight.description,
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      season: fight.season,
      session: fight.session,
      campaign_id: fight.campaign_id,
      created_at: fight.created_at,
      updated_at: fight.updated_at
    }
  end

  defp fight_json_with_shots(fight) do
    base = fight_json(fight)

    shots =
      case Map.get(fight, :shots) do
        %Ecto.Association.NotLoaded{} -> []
        shots -> Enum.map(shots, &shot_json/1)
      end

    Map.put(base, :shots, shots)
  end

  defp shot_json(shot) do
    %{
      id: shot.id,
      shot: shot.shot,
      position: shot.position,
      count: shot.count,
      color: shot.color,
      impairments: shot.impairments,
      location: shot.location,
      was_rammed_or_damaged: shot.was_rammed_or_damaged,
      fight_id: shot.fight_id,
      character_id: shot.character_id,
      vehicle_id: shot.vehicle_id,
      driver_id: shot.driver_id,
      driving_id: shot.driving_id,
      character: character_summary(shot.character),
      vehicle: vehicle_summary(shot.vehicle),
      driver: character_summary(shot.driver),
      driving: vehicle_summary(shot.driving),
      created_at: shot.created_at,
      updated_at: shot.updated_at
    }
  end

  defp character_summary(nil), do: nil
  defp character_summary(%Ecto.Association.NotLoaded{}), do: nil

  defp character_summary(character) do
    %{
      id: character.id,
      name: character.name,
      character_type: character.character_type,
      archetype: character.archetype,
      image_url: character.image_url
    }
  end

  defp vehicle_summary(nil), do: nil
  defp vehicle_summary(%Ecto.Association.NotLoaded{}), do: nil

  defp vehicle_summary(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      color: vehicle.color,
      image_url: vehicle.image_url,
      impairments: vehicle.impairments
    }
  end
end
