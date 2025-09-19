defmodule ShotElixirWeb.Api.V2.SiteJSON do
  def index(%{sites: data}) when is_map(data) do
    # Handle paginated response with metadata
    %{
      sites: Enum.map(data.sites, &site_json/1),
      factions: data[:factions] || [],
      meta: data[:meta] || %{},
      is_autocomplete: data[:is_autocomplete] || false
    }
  end

  def index(%{sites: sites}) when is_list(sites) do
    # Handle simple list response
    %{sites: Enum.map(sites, &site_json/1)}
  end

  def show(%{site: site}) do
    %{site: site_json_with_attunements(site)}
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

  defp site_json(site) when is_map(site) do
    %{
      id: Map.get(site, :id),
      name: Map.get(site, :name),
      description: Map.get(site, :description),
      active: Map.get(site, :active, true),
      campaign_id: Map.get(site, :campaign_id),
      faction_id: Map.get(site, :faction_id),
      juncture_id: Map.get(site, :juncture_id),
      faction:
        case Map.get(site, :faction) do
          %Ecto.Association.NotLoaded{} -> nil
          nil -> nil
          faction when is_map(faction) -> %{
            id: Map.get(faction, :id),
            name: Map.get(faction, :name)
          }
          _ -> nil
        end,
      juncture:
        case Map.get(site, :juncture) do
          %Ecto.Association.NotLoaded{} -> nil
          nil -> nil
          juncture when is_map(juncture) -> %{
            id: Map.get(juncture, :id),
            name: Map.get(juncture, :name)
          }
          _ -> nil
        end,
      created_at: Map.get(site, :created_at),
      updated_at: Map.get(site, :updated_at)
    }
  end

  defp site_json_with_attunements(site) do
    base = site_json(site)

    attunements =
      if Ecto.assoc_loaded?(site.attunements) do
        Enum.map(site.attunements, fn attunement ->
          %{
            id: attunement.id,
            character_id: attunement.character_id,
            character:
              if Ecto.assoc_loaded?(attunement.character) && attunement.character do
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
