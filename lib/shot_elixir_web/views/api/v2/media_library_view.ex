defmodule ShotElixirWeb.Api.V2.MediaLibraryView do
  @moduledoc """
  View for rendering Media Library JSON responses.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Media.MediaImage

  def render("index.json", %{images: images, meta: meta, stats: stats}) do
    # Batch fetch all entity names to avoid N+1 queries
    entity_names = batch_fetch_entity_names(images)

    %{
      images: Enum.map(images, fn image -> render_image(image, entity_names) end),
      meta: meta,
      stats: stats
    }
  end

  def render("show.json", %{image: image}) do
    render_image_full(image)
  end

  def render("search.json", %{images: images, meta: meta}) do
    # Batch fetch all entity names to avoid N+1 queries
    entity_names = batch_fetch_entity_names(images)

    %{
      images: Enum.map(images, fn image -> render_image_with_tags(image, entity_names) end),
      meta: meta
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  # Render image with AI tags (for search results)
  defp render_image_with_tags(%MediaImage{} = image, entity_names) do
    entity_name =
      if image.status == "attached" && image.entity_type && image.entity_id do
        Map.get(entity_names, {image.entity_type, image.entity_id})
      else
        nil
      end

    %{
      id: image.id,
      campaign_id: image.campaign_id,
      source: image.source,
      entity_type: image.entity_type,
      entity_id: image.entity_id,
      entity_name: entity_name,
      status: image.status,
      imagekit_url: image.imagekit_url,
      thumbnail_url: MediaImage.thumbnail_url(image),
      filename: image.filename,
      byte_size: image.byte_size,
      width: image.width,
      height: image.height,
      ai_provider: image.ai_provider,
      ai_tags: render_ai_tags(image.ai_tags),
      inserted_at: image.inserted_at,
      updated_at: image.updated_at
    }
  end

  # Render image for list view (lighter payload)
  defp render_image(%MediaImage{} = image, entity_names) do
    entity_name =
      if image.status == "attached" && image.entity_type && image.entity_id do
        Map.get(entity_names, {image.entity_type, image.entity_id})
      else
        nil
      end

    %{
      id: image.id,
      campaign_id: image.campaign_id,
      source: image.source,
      entity_type: image.entity_type,
      entity_id: image.entity_id,
      entity_name: entity_name,
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

  # Batch fetch entity names for all images to avoid N+1 queries
  # Returns a map of {entity_type, entity_id} => name
  defp batch_fetch_entity_names(images) do
    # Group images by entity type
    grouped =
      images
      |> Enum.filter(&(&1.status == "attached" && &1.entity_type && &1.entity_id))
      |> Enum.group_by(& &1.entity_type, & &1.entity_id)
      |> Enum.map(fn {type, ids} -> {type, Enum.uniq(ids)} end)
      |> Map.new()

    # Fetch names for each entity type in batch
    Enum.reduce(grouped, %{}, fn {entity_type, ids}, acc ->
      names = fetch_entity_names_by_type(entity_type, ids)
      Map.merge(acc, names)
    end)
  end

  # Batch fetch names for a specific entity type
  defp fetch_entity_names_by_type("Character", ids) do
    from(c in ShotElixir.Characters.Character, where: c.id in ^ids, select: {c.id, c.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Character", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("Vehicle", ids) do
    from(v in ShotElixir.Vehicles.Vehicle, where: v.id in ^ids, select: {v.id, v.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Vehicle", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("Weapon", ids) do
    from(w in ShotElixir.Weapons.Weapon, where: w.id in ^ids, select: {w.id, w.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Weapon", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("Schtick", ids) do
    from(s in ShotElixir.Schticks.Schtick, where: s.id in ^ids, select: {s.id, s.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Schtick", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("Site", ids) do
    from(s in ShotElixir.Sites.Site, where: s.id in ^ids, select: {s.id, s.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Site", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("Faction", ids) do
    from(f in ShotElixir.Factions.Faction, where: f.id in ^ids, select: {f.id, f.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Faction", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("Party", ids) do
    from(p in ShotElixir.Parties.Party, where: p.id in ^ids, select: {p.id, p.name})
    |> Repo.all()
    |> Enum.map(fn {id, name} -> {{"Party", id}, name} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type("User", ids) do
    from(u in ShotElixir.Accounts.User, where: u.id in ^ids, select: {u.id, u.name, u.email})
    |> Repo.all()
    |> Enum.map(fn {id, name, email} -> {{"User", id}, name || email} end)
    |> Map.new()
  end

  defp fetch_entity_names_by_type(_type, _ids), do: %{}

  # Get the name of the associated entity if attached (for show view - single query is fine)
  defp get_entity_name(%MediaImage{status: "attached", entity_type: type, entity_id: id})
       when not is_nil(type) and not is_nil(id) do
    names = fetch_entity_names_by_type(type, [id])
    Map.get(names, {type, id})
  end

  defp get_entity_name(_), do: nil

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Render AI tags for JSON response
  defp render_ai_tags(nil), do: []
  defp render_ai_tags(tags) when is_list(tags) do
    Enum.map(tags, fn tag ->
      %{
        name: tag["name"] || tag[:name],
        confidence: tag["confidence"] || tag[:confidence],
        source: tag["source"] || tag[:source]
      }
    end)
  end
end
