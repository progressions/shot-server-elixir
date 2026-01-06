defmodule ShotElixir.Media do
  @moduledoc """
  The Media context for managing AI-generated images and the media library.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Media.AiGeneratedImage
  alias ShotElixir.Services.ImagekitService
  alias ShotElixir.ActiveStorage

  @doc """
  Lists all images for a campaign, including both entity-attached images and orphan AI images.

  ## Parameters
    - campaign_id: UUID of the campaign
    - params: Map with optional filters:
      - "status" - "orphan", "attached", or "all" (default: "all")
      - "entity_type" - Filter by entity type (e.g., "Character")
      - "page" - Page number (default: 1)
      - "per_page" - Items per page (default: 50)

  ## Returns
    %{images: [%AiGeneratedImage{}], meta: %{total: n, page: n, per_page: n}}
  """
  def list_campaign_images(campaign_id, params \\ %{}) do
    per_page = get_int_param(params, "per_page", 50)
    page = get_int_param(params, "page", 1)
    offset = (page - 1) * per_page

    # Base query
    query =
      from i in AiGeneratedImage,
        where: i.campaign_id == ^campaign_id,
        order_by: [desc: i.inserted_at]

    # Apply status filter
    query =
      case params["status"] do
        "orphan" -> from i in query, where: i.status == "orphan"
        "attached" -> from i in query, where: i.status == "attached"
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
        total: total,
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
    query = from i in AiGeneratedImage, where: i.campaign_id == ^campaign_id

    total_count = Repo.aggregate(query, :count, :id)

    orphan_count =
      from(i in query, where: i.status == "orphan")
      |> Repo.aggregate(:count, :id)

    attached_count =
      from(i in query, where: i.status == "attached")
      |> Repo.aggregate(:count, :id)

    total_size =
      from(i in query, where: not is_nil(i.byte_size))
      |> Repo.aggregate(:sum, :byte_size) || 0

    %{
      total_count: total_count,
      orphan_count: orphan_count,
      attached_count: attached_count,
      total_size_bytes: total_size
    }
  end

  @doc """
  Gets a single AI-generated image by ID.
  """
  def get_image(id) do
    Repo.get(AiGeneratedImage, id)
  end

  @doc """
  Gets a single AI-generated image by ID.
  Raises if not found.
  """
  def get_image!(id) do
    Repo.get!(AiGeneratedImage, id)
  end

  @doc """
  Finds an AI-generated image by ImageKit file ID.
  """
  def get_image_by_imagekit_id(imagekit_file_id) do
    Repo.get_by(AiGeneratedImage, imagekit_file_id: imagekit_file_id)
  end

  @doc """
  Finds an AI-generated image by ImageKit URL.
  """
  def get_image_by_url(imagekit_url) do
    Repo.get_by(AiGeneratedImage, imagekit_url: imagekit_url)
  end

  @doc """
  Creates a new AI-generated image record.

  ## Parameters
    attrs - Map containing:
      - campaign_id (required)
      - imagekit_file_id (required)
      - imagekit_url (required)
      - imagekit_file_path
      - filename
      - content_type
      - byte_size
      - width
      - height
      - prompt
      - ai_provider
      - generated_by_id
  """
  def create_ai_image(attrs) do
    %AiGeneratedImage{}
    |> AiGeneratedImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Attaches an orphan image to an entity.
  Updates the ai_generated_image record and creates ActiveStorage records.

  ## Parameters
    - image: AiGeneratedImage struct or ID
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity
  """
  def attach_to_entity(%AiGeneratedImage{} = image, entity_type, entity_id) do
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

    # Create ActiveStorage attachment
    case ActiveStorage.attach_image(entity_type, entity_id, upload_result) do
      {:ok, _attachment} ->
        # Update the ai_generated_image record
        image
        |> AiGeneratedImage.attach_changeset(entity_type, entity_id)
        |> Repo.update()

      {:error, _} = error ->
        error
    end
  end

  def attach_to_entity(image_id, entity_type, entity_id) when is_binary(image_id) do
    case get_image(image_id) do
      nil -> {:error, :not_found}
      image -> attach_to_entity(image, entity_type, entity_id)
    end
  end

  @doc """
  Deletes an AI-generated image.
  Removes from database, ImageKit, and un-associates from entity if attached.
  """
  def delete_image(%AiGeneratedImage{} = image) do
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
  Returns {:ok, %{deleted: count, failed: count}}
  """
  def bulk_delete_images(image_ids) when is_list(image_ids) do
    results =
      Enum.map(image_ids, fn id ->
        case delete_image(id) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end
      end)

    deleted = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &(&1 == :error))

    {:ok, %{deleted: deleted, failed: failed}}
  end

  @doc """
  Duplicates an image within ImageKit and creates a new database record.
  """
  def duplicate_image(%AiGeneratedImage{} = image) do
    # Copy in ImageKit
    source_path = image.imagekit_file_path || extract_path_from_url(image.imagekit_url)
    destination_folder = Path.dirname(source_path)

    case ImagekitService.copy_file(source_path, destination_folder) do
      {:ok, copy_result} ->
        # Create new record for the copy
        attrs = %{
          campaign_id: image.campaign_id,
          status: "orphan",
          imagekit_file_id: copy_result.file_id,
          imagekit_url: copy_result.url,
          imagekit_file_path: copy_result.name,
          filename: copy_result.metadata["name"] || image.filename,
          content_type: image.content_type,
          byte_size: copy_result.size || image.byte_size,
          width: copy_result.width || image.width,
          height: copy_result.height || image.height,
          prompt: image.prompt,
          ai_provider: image.ai_provider,
          generated_by_id: image.generated_by_id
        }

        create_ai_image(attrs)

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
  defp extract_path_from_url(url) when is_binary(url) do
    # URL format: https://ik.imagekit.io/nvqgwnjgv/chi-war-dev/characters/file.jpg
    # We want: characters/file.jpg
    case String.split(url, ~r/chi-war-(?:dev|prod|test)\//) do
      [_, path] -> path
      _ -> Path.basename(url)
    end
  end

  defp extract_path_from_url(_), do: nil

  defp get_int_param(params, key, default) do
    case params[key] do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end
end
