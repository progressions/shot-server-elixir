defmodule ShotElixirWeb.Api.V2.FactionJSON do
  def index(%{factions: data}) when is_map(data) do
    # Handle paginated response with metadata
    %{
      factions: Enum.map(data.factions, &faction_json/1),
      meta: data[:meta] || %{}
    }
  end

  def index(%{factions: factions}) when is_list(factions) do
    # Handle simple list response
    %{factions: Enum.map(factions, &faction_json/1)}
  end

  def show(%{faction: faction}) do
    %{faction: faction_json(faction)}
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

  defp faction_json(faction) when is_map(faction) do
    %{
      id: Map.get(faction, :id),
      name: Map.get(faction, :name),
      description: Map.get(faction, :description),
      active: Map.get(faction, :active, true),
      campaign_id: Map.get(faction, :campaign_id),
      created_at: Map.get(faction, :created_at),
      updated_at: Map.get(faction, :updated_at)
    }
  end
end
