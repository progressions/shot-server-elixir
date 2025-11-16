defmodule ShotElixirWeb.Api.V2.SiteView do
  alias ShotElixir.JsonSanitizer

  def render("index.json", %{sites: data}) do
    site_serializer =
      if data.is_autocomplete, do: &render_site_autocomplete/1, else: &render_site_index/1

    %{
      sites: Enum.map(data.sites, site_serializer),
      factions: data.factions,
      meta: data.meta,
      is_autocomplete: data.is_autocomplete
    }
    |> JsonSanitizer.sanitize()
  end

  def render("show.json", %{site: site}) do
    %{site: render_site_detail(site)}
    |> JsonSanitizer.sanitize()
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render_site_index(site) do
    %{
      id: site.id,
      name: site.name,
      description: site.description,
      faction_id: site.faction_id,
      juncture_id: site.juncture_id,
      created_at: site.created_at,
      updated_at: site.updated_at,
      active: site.active,
      entity_class: "Site"
    }
  end

  def render_site_autocomplete(site) do
    %{
      id: site.id,
      name: site.name,
      entity_class: "Site"
    }
  end

  def render_site_detail(site) do
    base = %{
      id: site.id,
      name: site.name,
      description: site.description,
      faction_id: site.faction_id,
      juncture_id: site.juncture_id,
      created_at: site.created_at,
      updated_at: site.updated_at,
      active: site.active,
      campaign_id: site.campaign_id,
      entity_class: "Site"
    }

    # Add associations if loaded
    base
    |> add_if_loaded(:faction, site.faction)
    |> add_if_loaded(:juncture, site.juncture)
    |> add_if_loaded(:attunements, site.attunements)
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

  defp render_association(:juncture, nil), do: nil

  defp render_association(:juncture, juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description
    }
  end

  defp render_association(:attunements, attunements) when is_list(attunements) do
    Enum.map(attunements, fn attunement ->
      base = %{
        id: attunement.id,
        site_id: attunement.site_id,
        character_id: attunement.character_id
      }

      if Ecto.assoc_loaded?(attunement.character) do
        Map.put(base, :character, %{
          id: attunement.character.id,
          name: attunement.character.name,
          archetype: get_in(attunement.character.action_values, ["Archetype"]),
          entity_class: "Character"
        })
      else
        base
      end
    end)
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
