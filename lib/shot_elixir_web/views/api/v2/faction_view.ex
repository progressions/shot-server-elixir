defmodule ShotElixirWeb.Api.V2.FactionView do

  def render("index.json", %{data: data}) do
    faction_serializer =
      if data.is_autocomplete, do: &render_faction_autocomplete/1, else: &render_faction_index/1

    %{
      factions: Enum.map(data.factions, faction_serializer),
      meta: data.meta,
      is_autocomplete: data.is_autocomplete
    }
  end

  def render("show.json", %{faction: faction}) do
    render_faction_detail(faction)
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render_faction_index(faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      created_at: faction.created_at,
      updated_at: faction.updated_at,
      active: faction.active
    }
  end

  def render_faction_autocomplete(faction) do
    %{
      id: faction.id,
      name: faction.name
    }
  end

  def render_faction_detail(faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      created_at: faction.created_at,
      updated_at: faction.updated_at,
      active: faction.active,
      campaign_id: faction.campaign_id
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end