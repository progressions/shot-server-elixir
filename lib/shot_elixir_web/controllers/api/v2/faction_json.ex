defmodule ShotElixirWeb.Api.V2.FactionJSON do
  def index(%{factions: factions}) do
    %{factions: Enum.map(factions, &faction_json/1)}
  end

  def show(%{faction: faction}) do
    %{faction: faction_json(faction)}
  end

  def error(%{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    }
  end

  defp faction_json(faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      active: faction.active,
      campaign_id: faction.campaign_id,
      created_at: faction.created_at,
      updated_at: faction.updated_at
    }
  end
end