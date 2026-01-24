defmodule ShotElixir.Media do
  @moduledoc """
  The Media context for managing the media library.
  Tracks all images including manually uploaded and AI-generated images.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Media.MediaImage
  alias ShotElixir.Services.ImagekitService
  alias ShotElixir.ActiveStorage

  @valid_sort_fields ~w(inserted_at updated_at filename byte_size entity_type)

  @doc """
  Lists all images for a campaign with optional filtering.

  ## Parameters
    - campaign_id: UUID of the campaign
    - params: Map with optional filters:
      - "status" - "orphan", "attached", or "all" (default: "all")
      - "source" - "upload", "ai_generated", or "all" (default: "all")
      - "entity_type" - Filter by entity type (e.g., "Character")
      - "sort" - Field to sort by: "inserted_at", "updated_at", "filename", "byte_size", "entity_type" (default: "inserted_at")
      - "order" - Sort direction: "asc" or "desc" (default: "desc")
      - "page" - Page number (default: 1)
      - "per_page" - Items per page (default: 50)

  ## Returns
    %{images: [%MediaImage{}], meta: %{...}, stats: %{...}}
  """
  def list_campaign_images(campaign_id, params \\ %{}) do
    per_page = get_int_param(params, "per_page", 50)
    page = get_int_param(params, "page", 1)
    offset = (page - 1) * per_page

    # Parse sort parameters
    sort_field = get_sort_field(params["sort"])
    sort_order = if params["order"] == "asc", do: :asc, else: :desc

    # Base query (without ordering - we'll apply it dynamically)
    query =
      from i in MediaImage,
        where: i.campaign_id == ^campaign_id

    # Apply dynamic ordering
    query = apply_sort(query, sort_field, sort_order)

    # Apply status filter
    query =
      case params["status"] do
        "orphan" -> from i in query, where: i.status == "orphan"
        "attached" -> from i in query, where: i.status == "attached"
        _ -> query
      end

    # Apply source filter
    query =
      case params["source"] do
        "upload" -> from i in query, where: i.source == "upload"
        "ai_generated" -> from i in query, where: i.source == "ai_generated"
        "notion_import" -> from i in query, where: i.source == "notion_import"
        _ -> query
      end

    # Apply entity_type filter
    query =
      if params["entity_type"] && params["entity_type"] != "" do
        from i in query, where: i.entity_type == ^params["entity_type"]
      else
        query
      end

    # Get total count
    total = Repo.aggregate(query, :count, :id)

    # Get paginated results
    images =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Calculate stats
    stats = get_campaign_stats(campaign_id)

    %{
      images: images,
      meta: %{
        total_count: total,
        page: page,
        per_page: per_page,
        total_pages: ceil(total / per_page)
      },
      stats: stats
    }
  end

  @doc """
  Gets stats for all images in a campaign.
  """
  def get_campaign_stats(campaign_id) do
    query = from i in MediaImage, where: i.campaign_id == ^campaign_id

    total = Repo.aggregate(query, :count, :id)

    orphan =
      from(i in query, where: i.status == "orphan")
      |> Repo.aggregate(:count, :id)

    attached =
      from(i in query, where: i.status == "attached")
      |> Repo.aggregate(:count, :id)

    uploaded =
      from(i in query, where: i.source == "upload")
      |> Repo.aggregate(:count, :id)

    ai_generated =
      from(i in query, where: i.source == "ai_generated")
      |> Repo.aggregate(:count, :id)

    notion_imported =
      from(i in query, where: i.source == "notion_import")
      |> Repo.aggregate(:count, :id)

    total_size =
      from(i in query, where: not is_nil(i.byte_size))
      |> Repo.aggregate(:sum, :byte_size) || 0

    %{
      total: total,
      orphan: orphan,
      attached: attached,
      uploaded: uploaded,
      ai_generated: ai_generated,
      notion_imported: notion_imported,
      total_size_bytes: total_size
    }
  end

  @doc """
  Gets a single media image by ID.
  """
  def get_image(id) do
    Repo.get(MediaImage, id)
  end

  @doc """
  Gets a single media image by ID.
  Raises if not found.
  """
  def get_image!(id) do
    Repo.get!(MediaImage, id)
  end

  @doc """
  Finds a media image by ImageKit file ID.
  """
  def get_image_by_imagekit_id(imagekit_file_id) do
    Repo.get_by(MediaImage, imagekit_file_id: imagekit_file_id)
  end

  @doc """
  Finds a media image by ImageKit URL.
  """
  def get_image_by_url(imagekit_url) do
    Repo.get_by(MediaImage, imagekit_url: imagekit_url)
  end

  @doc """
  Finds a media image by ActiveStorage blob ID.
  """
  def get_image_by_blob_id(blob_id) do
    Repo.get_by(MediaImage, active_storage_blob_id: blob_id)
  end

  @doc """
  Creates a new media image record for an uploaded image.
  """
  def create_uploaded_image(attrs) do
    attrs = Map.put(attrs, :source, "upload")

    %MediaImage{}
    |> MediaImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new media image record for an AI-generated image.
  """
  def create_ai_image(attrs) do
    attrs = Map.put(attrs, :source, "ai_generated")

    %MediaImage{}
    |> MediaImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates or updates a media image record (generic, source must be specified in attrs).
  If an image with the same imagekit_file_id already exists, it will be updated.
  """
  def create_image(attrs) do
    # Check if image already exists by imagekit_file_id
    imagekit_file_id = attrs[:imagekit_file_id] || attrs["imagekit_file_id"]

    case get_image_by_imagekit_id(imagekit_file_id) do
      nil ->
        # Create new record
        %MediaImage{}
        |> MediaImage.changeset(attrs)
        |> Repo.insert()

      existing_image ->
        # Update existing record (e.g., when attaching an orphan)
        existing_image
        |> MediaImage.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Attaches an orphan image to an entity.
  Updates the media_image record and creates ActiveStorage records.

  ## Parameters
    - image: MediaImage struct or ID
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity

  ## Security
  Verifies that the entity belongs to the same campaign as the image to prevent
  cross-campaign data leaks.
  """
  def attach_to_entity(%MediaImage{} = image, entity_type, entity_id) do
    # Verify entity belongs to the same campaign as the image (security check)
    case verify_entity_campaign(entity_type, entity_id, image.campaign_id) do
      :ok ->
        do_attach_to_entity(image, entity_type, entity_id)

      {:error, :not_found} ->
        {:error, :entity_not_found}

      {:error, :campaign_mismatch} ->
        {:error, :unauthorized}
    end
  end

  def attach_to_entity(image_id, entity_type, entity_id) when is_binary(image_id) do
    case get_image(image_id) do
      nil -> {:error, :not_found}
      image -> attach_to_entity(image, entity_type, entity_id)
    end
  end

  defp do_attach_to_entity(%MediaImage{} = image, entity_type, entity_id) do
    # Build upload_result compatible with ActiveStorage.attach_image
    upload_result = %{
      file_id: image.imagekit_file_id,
      name: image.imagekit_file_path || extract_path_from_url(image.imagekit_url),
      url: image.imagekit_url,
      size: image.byte_size || 0,
      metadata: %{
        "fileType" => image.content_type || "image/jpeg"
      }
    }

    # Create ActiveStorage attachment - the attach_image function will also
    # update the existing media_image record via create_image (upsert)
    opts = [
      source: image.source,
      campaign_id: image.campaign_id
    ]

    case ActiveStorage.attach_image(entity_type, entity_id, upload_result, opts) do
      {:ok, _attachment} ->
        # Return the updated image (re-fetch to get updated blob_id)
        {:ok, get_image(image.id)}

      {:error, _} = error ->
        error
    end
  end

  # Verify that an entity belongs to the specified campaign
  defp verify_entity_campaign(entity_type, entity_id, campaign_id) do
    query =
      case entity_type do
        "Character" ->
          from(e in ShotElixir.Characters.Character,
            where: e.id == ^entity_id,
            select: e.campaign_id
          )

        "Vehicle" ->
          from(e in ShotElixir.Vehicles.Vehicle,
            where: e.id == ^entity_id,
            select: e.campaign_id
          )

        "Weapon" ->
          from(e in ShotElixir.Weapons.Weapon,
            where: e.id == ^entity_id,
            select: e.campaign_id
          )

        "Schtick" ->
          from(e in ShotElixir.Schticks.Schtick,
            where: e.id == ^entity_id,
            select: e.campaign_id
          )

        "Site" ->
          from(e in ShotElixir.Sites.Site, where: e.id == ^entity_id, select: e.campaign_id)

        "Faction" ->
          from(e in ShotElixir.Factions.Faction,
            where: e.id == ^entity_id,
            select: e.campaign_id
          )

        "Party" ->
          from(e in ShotElixir.Parties.Party, where: e.id == ^entity_id, select: e.campaign_id)

        "User" ->
          # Users don't have campaign_id - return :ok for User entity type
          :skip_check

        _ ->
          nil
      end

    case query do
      :skip_check ->
        :ok

      nil ->
        {:error, :not_found}

      query ->
        case Repo.one(query) do
          nil -> {:error, :not_found}
          ^campaign_id -> :ok
          _other_campaign -> {:error, :campaign_mismatch}
        end
    end
  end

  @doc """
  Deletes a media image.
  Removes from database, ImageKit, and un-associates from entity if attached.
  """
  def delete_image(%MediaImage{} = image) do
    # If attached, delete from ActiveStorage first
    if image.status == "attached" && image.entity_type && image.entity_id do
      ActiveStorage.delete_image(image.entity_type, image.entity_id)
    end

    # Delete from ImageKit
    case ImagekitService.delete_file(image.imagekit_file_id) do
      {:ok, :deleted} ->
        Repo.delete(image)

      {:error, _reason} ->
        # Even if ImageKit delete fails, remove from our database
        # The ImageKit file may already be gone or we may not have access
        Repo.delete(image)
    end
  end

  def delete_image(image_id) when is_binary(image_id) do
    case get_image(image_id) do
      nil -> {:error, :not_found}
      image -> delete_image(image)
    end
  end

  @doc """
  Bulk deletes multiple images.
  Returns {:ok, %{deleted: [ids], failed: [ids]}}
  """
  def bulk_delete_images(image_ids) when is_list(image_ids) do
    results =
      Enum.map(image_ids, fn id ->
        case delete_image(id) do
          {:ok, _} -> {:ok, id}
          {:error, _} -> {:error, id}
        end
      end)

    deleted =
      Enum.filter(results, fn {status, _} -> status == :ok end) |> Enum.map(fn {_, id} -> id end)

    failed =
      Enum.filter(results, fn {status, _} -> status == :error end)
      |> Enum.map(fn {_, id} -> id end)

    {:ok, %{deleted: deleted, failed: failed}}
  end

  @doc """
  Duplicates an image within ImageKit and creates a new database record.
  The duplicate is always created as an orphan.
  """
  def duplicate_image(%MediaImage{} = image) do
    # Always extract folder from URL since imagekit_file_path may be just the filename
    source_path = extract_path_from_url(image.imagekit_url)
    # Upload API expects folder without leading slash
    folder = Path.dirname(source_path) |> strip_leading_slash()

    # Upload from the original URL to create a copy with a unique filename
    upload_options = %{
      folder: folder,
      file_name: image.filename || "duplicate.jpg",
      use_unique_file_name: true
    }

    case ImagekitService.upload_from_url(image.imagekit_url, upload_options) do
      {:ok, upload_result} ->
        # Create new record for the copy (always orphan)
        attrs = %{
          campaign_id: image.campaign_id,
          source: image.source,
          status: "orphan",
          imagekit_file_id: upload_result.file_id,
          imagekit_url: upload_result.url,
          imagekit_file_path: upload_result.name,
          filename: upload_result.metadata["name"] || image.filename,
          content_type: image.content_type,
          byte_size: upload_result.size || image.byte_size,
          width: upload_result.width || image.width,
          height: upload_result.height || image.height,
          prompt: image.prompt,
          ai_provider: image.ai_provider,
          ai_tags: image.ai_tags || [],
          generated_by_id: image.generated_by_id,
          uploaded_by_id: image.uploaded_by_id
        }

        create_image(attrs)

      {:error, _} = error ->
        error
    end
  end

  def duplicate_image(image_id) when is_binary(image_id) do
    case get_image(image_id) do
      nil -> {:error, :not_found}
      image -> duplicate_image(image)
    end
  end

  # Helper to extract path from full ImageKit URL
  defp extract_path_from_url(url) when is_binary(url) and url != "" do
    # URL format: https://ik.imagekit.io/nvqgwnjgv/chi-war-dev/characters/file.jpg
    # We want: chi-war-dev/characters/file.jpg

    # Use a more precise regex that captures the path after the ImageKit ID
    case Regex.run(~r{^https?://ik\.imagekit\.io/[^/]+/(.+)$}, url) do
      [_full, path] when path != "" ->
        # Remove any query parameters or fragments
        path
        |> String.split("?")
        |> hd()
        |> String.split("#")
        |> hd()

      _ ->
        # Fallback: try to get basename if URL doesn't match expected format
        case URI.parse(url) do
          %URI{path: path} when is_binary(path) and path != "" ->
            Path.basename(path)

          _ ->
            nil
        end
    end
  end

  defp extract_path_from_url(_), do: nil

  # Helper to strip leading slash for ImageKit upload API folder parameter
  defp strip_leading_slash("/" <> rest), do: rest
  defp strip_leading_slash(path), do: path

  defp get_int_param(params, key, default) do
    case params[key] do
      nil ->
        default

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end
    end
  end

  # Helper to validate and convert sort field
  defp get_sort_field(nil), do: :inserted_at
  defp get_sort_field(""), do: :inserted_at

  defp get_sort_field(field) when is_binary(field) do
    if field in @valid_sort_fields do
      String.to_atom(field)
    else
      :inserted_at
    end
  end

  # Apply dynamic ordering to query
  defp apply_sort(query, field, :asc) do
    from i in query, order_by: [asc: field(i, ^field)]
  end

  defp apply_sort(query, field, :desc) do
    from i in query, order_by: [desc: field(i, ^field)]
  end

  @doc """
  Marks all images associated with an entity as orphaned.
  Used when an entity is deleted to preserve images for potential reuse or cleanup.

  ## Parameters
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity being deleted

  ## Returns
    {:ok, count} where count is the number of images orphaned
  """
  def orphan_images_for_entity(entity_type, entity_id) do
    {count, _} =
      from(i in MediaImage,
        where: i.entity_type == ^entity_type and i.entity_id == ^entity_id
      )
      |> Repo.update_all(set: [status: "orphan", entity_type: nil, entity_id: nil])

    {:ok, count}
  end

  @doc """
  Returns a query for orphaning images, suitable for use with Ecto.Multi.update_all.

  ## Example
      Multi.new()
      |> Multi.update_all(:orphan_images, Media.orphan_images_query("Character", character_id), [])
  """
  def orphan_images_query(entity_type, entity_id) do
    from(i in MediaImage,
      where: i.entity_type == ^entity_type and i.entity_id == ^entity_id,
      update: [set: [status: "orphan", entity_type: nil, entity_id: nil]]
    )
  end

  @doc """
  Searches images by AI-generated tags.

  ## Parameters
    - campaign_id: UUID of the campaign
    - search_terms: List of tag names to search for (case-insensitive)
    - params: Optional pagination params ("page", "per_page")

  ## Returns
    %{images: [%MediaImage{}], meta: %{...}}

  ## Example
      search_by_ai_tags(campaign_id, ["warrior", "cartoon"])
  """
  def search_by_ai_tags(campaign_id, search_terms, params \\ %{}) when is_list(search_terms) do
    per_page = get_int_param(params, "per_page", 50)
    page = get_int_param(params, "page", 1)
    offset = (page - 1) * per_page

    # Normalize search terms to lowercase
    normalized_terms = Enum.map(search_terms, &String.downcase/1)

    # Build query that matches any of the search terms in the ai_tags array
    # ai_tags is a jsonb[] (PostgreSQL array of JSONB), so we use unnest() not jsonb_array_elements()
    query =
      from i in MediaImage,
        where: i.campaign_id == ^campaign_id,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM unnest(?) AS tag WHERE LOWER(tag->>'name') LIKE ANY(?))",
            i.ai_tags,
            ^Enum.map(normalized_terms, &"%#{&1}%")
          ),
        order_by: [desc: i.inserted_at]

    total = Repo.aggregate(query, :count, :id)

    images =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      images: images,
      meta: %{
        total_count: total,
        page: page,
        per_page: per_page,
        total_pages: ceil(max(total, 1) / per_page),
        search_terms: search_terms
      }
    }
  end

  @doc """
  Gets all unique AI tag names for a campaign.
  Useful for building tag autocomplete or tag clouds.

  ## Returns
    List of unique tag names sorted alphabetically
  """
  def list_ai_tags(campaign_id) do
    # ai_tags is a jsonb[] (PostgreSQL array of JSONB), so we use unnest() not jsonb_array_elements()
    query = """
    SELECT DISTINCT LOWER(tag->>'name') as tag_name
    FROM media_images, unnest(ai_tags) AS tag
    WHERE campaign_id = $1 AND ai_tags IS NOT NULL AND array_length(ai_tags, 1) > 0
    ORDER BY tag_name
    """

    case Repo.query(query, [Ecto.UUID.dump!(campaign_id)]) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [name] -> name end)
      {:error, _} -> []
    end
  end

  @doc """
  Updates the AI tags for an existing media image.
  Used when fetching tags from ImageKit for existing images.
  """
  def update_ai_tags(%MediaImage{} = image, ai_tags) when is_list(ai_tags) do
    image
    |> MediaImage.changeset(%{ai_tags: ai_tags})
    |> Repo.update()
  end
end
