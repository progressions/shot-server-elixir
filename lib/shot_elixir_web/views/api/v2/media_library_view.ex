defmodule ShotElixirWeb.Api.V2.MediaLibraryView do
  @moduledoc """
  View for rendering Media Library JSON responses.
  """

  alias ShotElixir.Media.MediaImage

  def render("index.json", %{images: images, meta: meta, stats: stats}) do
    %{
      images: Enum.map(images, &render_image/1),
      meta: meta,
      stats: stats
    }
  end

  def render("show.json", %{image: image}) do
    render_image_full(image)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  # Render image for list view (lighter payload)
  defp render_image(%MediaImage{} = image) do
    %{
      id: image.id,
      campaign_id: image.campaign_id,
      source: image.source,
      entity_type: image.entity_type,
      entity_id: image.entity_id,
      entity_name: get_entity_name(image),
      status: image.status,
      imagekit_url: image.imagekit_url,
      thumbnail_url: MediaImage.thumbnail_url(image),
      filename: image.filename,
      byte_size: image.byte_size,
      width: image.width,
      height: image.height,
      ai_provider: image.ai_provider,
      inserted_at: image.inserted_at,
      updated_at: image.updated_at
    }
  end

  # Render full image details for show view
  defp render_image_full(%MediaImage{} = image) do
    %{
      id: image.id,
      campaign_id: image.campaign_id,
      source: image.source,
      entity_type: image.entity_type,
      entity_id: image.entity_id,
      entity_name: get_entity_name(image),
      status: image.status,
      active_storage_blob_id: image.active_storage_blob_id,
      imagekit_file_id: image.imagekit_file_id,
      imagekit_url: image.imagekit_url,
      imagekit_file_path: image.imagekit_file_path,
      thumbnail_url: MediaImage.thumbnail_url(image),
      filename: image.filename,
      content_type: image.content_type,
      byte_size: image.byte_size,
      width: image.width,
      height: image.height,
      prompt: image.prompt,
      ai_provider: image.ai_provider,
      generated_by_id: image.generated_by_id,
      uploaded_by_id: image.uploaded_by_id,
      inserted_at: image.inserted_at,
      updated_at: image.updated_at
    }
  end

  # Get the name of the associated entity if attached
  defp get_entity_name(%MediaImage{status: "attached", entity_type: type, entity_id: id})
       when not is_nil(type) and not is_nil(id) do
    case type do
      "Character" -> get_character_name(id)
      "Vehicle" -> get_vehicle_name(id)
      "Weapon" -> get_weapon_name(id)
      "Schtick" -> get_schtick_name(id)
      "Site" -> get_site_name(id)
      "Faction" -> get_faction_name(id)
      "Party" -> get_party_name(id)
      "User" -> get_user_name(id)
      _ -> nil
    end
  end

  defp get_entity_name(_), do: nil

  # Entity name lookup helpers
  defp get_character_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Characters.Character, id) do
      nil -> nil
      character -> character.name
    end
  end

  defp get_vehicle_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Vehicles.Vehicle, id) do
      nil -> nil
      vehicle -> vehicle.name
    end
  end

  defp get_weapon_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Weapons.Weapon, id) do
      nil -> nil
      weapon -> weapon.name
    end
  end

  defp get_schtick_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Schticks.Schtick, id) do
      nil -> nil
      schtick -> schtick.name
    end
  end

  defp get_site_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Sites.Site, id) do
      nil -> nil
      site -> site.name
    end
  end

  defp get_faction_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Factions.Faction, id) do
      nil -> nil
      faction -> faction.name
    end
  end

  defp get_party_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Parties.Party, id) do
      nil -> nil
      party -> party.name
    end
  end

  defp get_user_name(id) do
    case ShotElixir.Repo.get(ShotElixir.Accounts.User, id) do
      nil -> nil
      user -> user.name || user.email
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
