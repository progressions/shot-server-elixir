defmodule ShotElixirWeb.Api.V2.SiteJSON do
  def index(%{sites: sites}) do
    %{sites: Enum.map(sites, &site_json/1)}
  end

  def show(%{site: site}) do
    %{site: site_json_with_attunements(site)}
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

  defp site_json(site) do
    %{
      id: site.id,
      name: site.name,
      description: site.description,
      active: site.active,
      campaign_id: site.campaign_id,
      faction_id: site.faction_id,
      juncture_id: site.juncture_id,
      faction: if Ecto.assoc_loaded?(site.faction) && site.faction do
        %{
          id: site.faction.id,
          name: site.faction.name
        }
      else
        nil
      end,
      juncture: if Ecto.assoc_loaded?(site.juncture) && site.juncture do
        %{
          id: site.juncture.id,
          name: site.juncture.name
        }
      else
        nil
      end,
      created_at: site.created_at,
      updated_at: site.updated_at
    }
  end

  defp site_json_with_attunements(site) do
    base = site_json(site)

    attunements = if Ecto.assoc_loaded?(site.attunements) do
      Enum.map(site.attunements, fn attunement ->
        %{
          id: attunement.id,
          character_id: attunement.character_id,
          character: if Ecto.assoc_loaded?(attunement.character) && attunement.character do
            %{
              id: attunement.character.id,
              name: attunement.character.name
            }
          else
            nil
          end
        }
      end)
    else
      []
    end

    Map.put(base, :attunements, attunements)
  end
end