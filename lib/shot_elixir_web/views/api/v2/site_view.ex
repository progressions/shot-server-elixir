defmodule ShotElixirWeb.Api.V2.SiteView do
  def render("index.json", %{sites: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{sites: sites, meta: meta, is_autocomplete: is_autocomplete} ->
        site_serializer =
          if is_autocomplete, do: &render_site_autocomplete/1, else: &render_site/1

        %{
          sites: Enum.map(sites, site_serializer),
          meta: meta
        }

      %{sites: sites, meta: meta} ->
        %{
          sites: Enum.map(sites, &render_site/1),
          meta: meta
        }

      sites when is_list(sites) ->
        # Legacy format for backward compatibility
        %{
          sites: Enum.map(sites, &render_site/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(sites),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{site: site}) do
    render_site(site)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_site(site) do
    %{
      id: site.id,
      name: site.name,
      description: site.description,
      campaign_id: site.campaign_id,
      created_at: site.created_at,
      updated_at: site.updated_at,
      image_url: site.image_url,
      entity_class: "SiteView"
    }
  end

  defp render_site_autocomplete(site) do
    %{
      id: site.id,
      name: site.name,
      entity_class: "SiteView"
    }
  end

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(errors), do: errors
end