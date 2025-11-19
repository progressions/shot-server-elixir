defmodule ShotElixirWeb.Api.V2.SiteView do
  def render("index.json", %{sites: sites, meta: meta}) do
    %{
      sites: Enum.map(sites, &render_site/1),
      meta: meta
    }
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
      active: site.active,
      faction_id: site.faction_id,
      campaign_id: site.campaign_id,
      juncture_id: site.juncture_id,
      character_ids: get_character_ids(site),
      created_at: site.created_at,
      updated_at: site.updated_at,
      image_url: get_image_url(site),
      characters: render_characters_if_loaded(site),
      faction: render_faction_if_loaded(site),
      image_positions: render_image_positions_if_loaded(site),
      attunements: render_attunements_if_loaded(site),
      entity_class: "Site"
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

  defp get_character_ids(site) do
    case Map.get(site, :attunements) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      attunements ->
        attunements
        |> Enum.map(fn attunement -> attunement.character end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(& &1.id)
    end
  end

  defp render_characters_if_loaded(site) do
    case Map.get(site, :attunements) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      attunements ->
        characters =
          attunements
          |> Enum.map(fn attunement -> attunement.character end)
          |> Enum.filter(&(&1 != nil))

        # Load image URLs for all characters efficiently
        characters_with_images = ShotElixir.ImageLoader.load_image_urls(characters, "Character")
        Enum.map(characters_with_images, &render_character_lite/1)
    end
  end

  defp render_faction_if_loaded(site) do
    case Map.get(site, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_lite(faction)
    end
  end

  defp render_image_positions_if_loaded(site) do
    case Map.get(site, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_attunements_if_loaded(site) do
    case Map.get(site, :attunements) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      attunements -> Enum.map(attunements, &render_attunement/1)
    end
  end

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  defp render_faction_lite(faction) do
    %{
      id: faction.id,
      name: faction.name,
      entity_class: "Faction"
    }
  end

  defp render_image_position(position) do
    %{
      id: position.id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides
    }
  end

  defp render_attunement(attunement) do
    %{
      id: attunement.id,
      character_id: attunement.character_id,
      site_id: attunement.site_id,
      created_at: attunement.created_at,
      updated_at: attunement.updated_at
    }
  end

  # Rails-compatible image URL handling
  defp get_image_url(record) when is_map(record) do
    # Check if image_url is already in the record (pre-loaded)
    case Map.get(record, :image_url) do
      nil ->
        # Try to get entity type from struct, fallback to nil if plain map
        entity_type =
          case Map.get(record, :__struct__) do
            # Plain map, skip ActiveStorage lookup
            nil -> nil
            struct_module -> struct_module |> Module.split() |> List.last()
          end

        if entity_type && Map.get(record, :id) do
          ShotElixir.ActiveStorage.get_image_url(entity_type, record.id)
        else
          nil
        end

      url ->
        url
    end
  end

  defp get_image_url(_), do: nil
end
