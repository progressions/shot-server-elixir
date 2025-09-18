defmodule ShotElixirWeb.Api.V2.JunctureJSON do
  def index(%{junctures: junctures}) do
    %{junctures: Enum.map(junctures, &juncture_json/1)}
  end

  def show(%{juncture: juncture}) do
    %{juncture: juncture_json(juncture)}
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

  defp juncture_json(juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description,
      active: juncture.active,
      notion_page_id: juncture.notion_page_id,
      campaign_id: juncture.campaign_id,
      faction_id: juncture.faction_id,
      faction: if juncture.faction do
        %{
          id: juncture.faction.id,
          name: juncture.faction.name
        }
      else
        nil
      end,
      created_at: juncture.created_at,
      updated_at: juncture.updated_at
    }
  end
end