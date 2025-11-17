defmodule ShotElixirWeb.Api.V2.ShotJSON do
  def show(%{shot: shot}) do
    shot_json(shot)
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

  defp shot_json(shot) do
    %{
      id: shot.id,
      shot: shot.shot,
      acted: shot.acted,
      hidden: shot.hidden,
      fight_id: shot.fight_id,
      character_id: shot.character_id,
      vehicle_id: shot.vehicle_id,
      created_at: shot.created_at,
      updated_at: shot.updated_at,
      entity_class: "Shot"
    }
  end
end
