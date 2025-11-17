defmodule ShotElixirWeb.Api.V2.JunctureJSON do
  def index(%{junctures: data}) when is_map(data) do
    # Handle paginated response with metadata
    %{
      junctures: Enum.map(data.junctures, &juncture_json/1),
      factions: data[:factions] || [],
      meta: data[:meta] || %{}
    }
  end

  def index(%{junctures: junctures}) when is_list(junctures) do
    # Handle simple list response
    %{junctures: Enum.map(junctures, &juncture_json/1)}
  end

  def show(%{juncture: juncture}) do
    juncture_json(juncture)
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

  defp juncture_json(juncture) when is_map(juncture) do
    # Handle both struct and map format
    faction =
      case Map.get(juncture, :faction) do
        %Ecto.Association.NotLoaded{} ->
          nil

        nil ->
          nil

        faction when is_map(faction) ->
          %{
            id: Map.get(faction, :id),
            name: Map.get(faction, :name)
          }

        _ ->
          nil
      end

    %{
      id: Map.get(juncture, :id),
      name: Map.get(juncture, :name),
      description: Map.get(juncture, :description),
      active: Map.get(juncture, :active, true),
      notion_page_id: Map.get(juncture, :notion_page_id),
      campaign_id: Map.get(juncture, :campaign_id),
      faction_id: Map.get(juncture, :faction_id),
      faction: faction,
      created_at: Map.get(juncture, :created_at),
      updated_at: Map.get(juncture, :updated_at)
    }
  end
end
