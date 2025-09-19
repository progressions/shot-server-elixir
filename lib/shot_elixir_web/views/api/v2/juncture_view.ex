defmodule ShotElixirWeb.Api.V2.JunctureView do

  def render("index.json", %{data: data}) do
    juncture_serializer =
      if data.is_autocomplete, do: &render_juncture_autocomplete/1, else: &render_juncture_index/1

    %{
      junctures: Enum.map(data.junctures, juncture_serializer),
      factions: data.factions,
      meta: data.meta,
      is_autocomplete: data.is_autocomplete
    }
  end

  def render("show.json", %{juncture: juncture}) do
    render_juncture_detail(juncture)
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render_juncture_index(juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description,
      faction_id: juncture.faction_id,
      created_at: juncture.created_at,
      updated_at: juncture.updated_at,
      active: juncture.active
    }
  end

  def render_juncture_autocomplete(juncture) do
    %{
      id: juncture.id,
      name: juncture.name
    }
  end

  def render_juncture_detail(juncture) do
    base = %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description,
      faction_id: juncture.faction_id,
      created_at: juncture.created_at,
      updated_at: juncture.updated_at,
      active: juncture.active,
      campaign_id: juncture.campaign_id
    }

    # Add associations if loaded
    base
    |> add_if_loaded(:faction, juncture.faction)
  end

  defp add_if_loaded(base, key, association) do
    if Ecto.assoc_loaded?(association) do
      Map.put(base, key, render_association(key, association))
    else
      base
    end
  end

  defp render_association(:faction, nil), do: nil
  defp render_association(:faction, faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description
    }
  end

  defp render_association(_, association), do: association

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end