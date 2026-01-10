defmodule ShotElixir.ActiveStorage do
  @moduledoc """
  Context for managing ActiveStorage attachments.
  Provides read and write access to image URLs and metadata.
  """

  import Ecto.Query
  alias ShotElixir.Repo
  alias ShotElixir.ActiveStorage.{Attachment, Blob}
  alias ShotElixir.Services.ImagekitService
  alias ShotElixir.Media
  alias ShotElixirWeb.CampaignChannel
  alias Ecto.Multi

  @doc """
  Gets the image URL for a record by querying ActiveStorage tables.
  Returns nil if no image is attached.

  ## Examples

      iex> get_image_url("Character", character_id)
      "https://ik.imagekit.io/nvqgwnjgv/chi-war-dev/characters/image.jpg"

      iex> get_image_url("Character", character_with_no_image_id)
      nil
  """
  def get_image_url(record_type, record_id)
      when is_binary(record_type) and is_binary(record_id) do
    query =
      from a in Attachment,
        join: b in Blob,
        on: a.blob_id == b.id,
        where: a.record_type == ^record_type and a.record_id == ^record_id and a.name == "image",
        order_by: [desc: a.created_at],
        limit: 1,
        select: b

    case Repo.one(query) do
      nil -> nil
      blob -> build_image_url_from_blob(blob)
    end
  end

  def get_image_url(_record_type, _record_id), do: nil

  @doc """
  Loads image URLs for multiple records efficiently using a single query.
  Returns a map of record_id => image_url.

  ## Examples

      iex> get_image_urls_for_records("Character", [id1, id2, id3])
      %{id1 => "https://...", id2 => nil, id3 => "https://..."}
  """
  def get_image_urls_for_records(record_type, record_ids)
      when is_binary(record_type) and is_list(record_ids) do
    query =
      from a in Attachment,
        join: b in Blob,
        on: a.blob_id == b.id,
        where: a.record_type == ^record_type and a.record_id in ^record_ids and a.name == "image",
        select: {a.record_id, b}

    results = Repo.all(query)

    # Build map with URLs for records that have images
    url_map =
      results
      |> Enum.map(fn {record_id, blob} -> {record_id, build_image_url_from_blob(blob)} end)
      |> Map.new()

    # Include nil for records without images
    record_ids
    |> Enum.map(fn id -> {id, Map.get(url_map, id)} end)
    |> Map.new()
  end

  def get_image_urls_for_records(_record_type, _record_ids), do: %{}

  # Builds an ImageKit URL from a Rails ActiveStorage blob.
  # Follows the same logic as Rails WithImagekit concern.
  defp build_image_url_from_blob(%Blob{} = blob) do
    metadata = Blob.decoded_metadata(blob)

    # Try legacy URL fields first (direct ImageKit URL)
    legacy_url =
      [
        metadata["imagekit_url"],
        metadata["url"]
      ]
      |> Enum.find(&(&1 not in [nil, ""]))

    if legacy_url do
      legacy_url
    else
      # Build URL from path or key
      path_source =
        metadata["imagekit_file_path"] ||
          blob.key

      build_imagekit_url(path_source)
    end
  end

  defp build_imagekit_url(nil), do: nil
  defp build_imagekit_url(""), do: nil

  defp build_imagekit_url(path) do
    endpoint = ImagekitService.url_endpoint()

    if endpoint && path do
      endpoint = String.trim_trailing(endpoint, "/")
      path = String.trim_leading(path, "/")
      "#{endpoint}/#{path}"
    else
      nil
    end
  end

  @doc """
  Creates a blob record and attaches it to an entity.
  Also creates a media_images record for the Media Library.
  Returns {:ok, attachment} or {:error, changeset}.

  ## Parameters
    - record_type: "Character", "Vehicle", etc.
    - record_id: UUID of the entity
    - upload_result: Map from ImagekitService.upload_file/2 containing:
      - :file_id
      - :name
      - :url
      - :size
      - :metadata (full ImageKit response)
    - opts: Optional keyword list with:
      - :source - "upload" or "ai_generated" (default: "upload")
      - :uploaded_by_id - UUID of user who uploaded
      - :campaign_id - UUID of campaign (auto-detected if not provided)

  ## Examples
      iex> attach_image("Character", character_id, upload_result)
      {:ok, %Attachment{}}

      iex> attach_image("Character", character_id, upload_result, uploaded_by_id: user_id)
      {:ok, %Attachment{}}
  """
  def attach_image(record_type, record_id, upload_result, opts \\ []) do
    source = Keyword.get(opts, :source, "upload")
    uploaded_by_id = Keyword.get(opts, :uploaded_by_id)

    campaign_id =
      Keyword.get(opts, :campaign_id) || get_campaign_id_for_entity(record_type, record_id)

    Multi.new()
    |> Multi.run(:delete_existing, fn repo, _changes ->
      # Delete existing attachment for this entity if it exists
      query =
        from a in Attachment,
          where:
            a.record_type == ^record_type and
              a.record_id == ^record_id and
              a.name == "image"

      case repo.one(query) do
        nil ->
          {:ok, nil}

        existing_attachment ->
          # Delete attachment first (foreign key constraint)
          repo.delete(existing_attachment)

          # Then delete the old blob
          case repo.get(Blob, existing_attachment.blob_id) do
            nil ->
              {:ok, existing_attachment}

            blob ->
              repo.delete(blob)
              {:ok, existing_attachment}
          end
      end
    end)
    |> Multi.insert(:blob, fn _changes ->
      # Build metadata JSON string (Rails format)
      metadata =
        Jason.encode!(%{
          "imagekit_url" => upload_result.url,
          "imagekit_file_path" => upload_result.name,
          "imagekit_file_id" => upload_result.file_id
        })

      blob_attrs = %{
        key: upload_result.name,
        filename: Path.basename(upload_result.name),
        content_type: upload_result.metadata["fileType"] || "image/jpeg",
        metadata: metadata,
        service_name: "imagekit",
        byte_size: upload_result.size,
        checksum: generate_checksum(upload_result.name),
        created_at: DateTime.utc_now()
      }

      Blob.changeset(%Blob{}, blob_attrs)
    end)
    |> Multi.insert(:attachment, fn %{blob: blob} ->
      attachment_attrs = %{
        name: "image",
        record_type: record_type,
        record_id: record_id,
        blob_id: blob.id,
        created_at: DateTime.utc_now()
      }

      Attachment.changeset(%Attachment{}, attachment_attrs)
    end)
    |> Multi.run(:media_image, fn _repo, %{blob: blob} ->
      # Create media_images record for Media Library
      if campaign_id do
        media_attrs = %{
          campaign_id: campaign_id,
          source: source,
          entity_type: record_type,
          entity_id: record_id,
          status: "attached",
          active_storage_blob_id: blob.id,
          imagekit_file_id: upload_result.file_id,
          imagekit_url: upload_result.url,
          imagekit_file_path: upload_result.name,
          filename: Path.basename(upload_result.name),
          content_type: upload_result.metadata["fileType"] || "image/jpeg",
          byte_size: upload_result.size,
          uploaded_by_id: uploaded_by_id
        }

        Media.create_image(media_attrs)
      else
        # Skip media_images for entities without campaigns (e.g., Users)
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{attachment: attachment}} ->
        # Broadcast to media library if campaign context exists
        if campaign_id do
          require Logger
          Logger.info("📸 MEDIA: Broadcasting image reload for campaign #{campaign_id}")
          CampaignChannel.broadcast_entity_reload(campaign_id, "Image")
        end

        {:ok, attachment}

      {:error, _failed_operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # Get campaign_id for an entity by looking it up in the database
  defp get_campaign_id_for_entity("Character", id) do
    query_campaign_id("characters", id)
  end

  defp get_campaign_id_for_entity("Vehicle", id) do
    query_campaign_id("vehicles", id)
  end

  defp get_campaign_id_for_entity("Weapon", id) do
    query_campaign_id("weapons", id)
  end

  defp get_campaign_id_for_entity("Schtick", id) do
    query_campaign_id("schticks", id)
  end

  defp get_campaign_id_for_entity("Site", id) do
    query_campaign_id("sites", id)
  end

  defp get_campaign_id_for_entity("Faction", id) do
    query_campaign_id("factions", id)
  end

  defp get_campaign_id_for_entity("Party", id) do
    query_campaign_id("parties", id)
  end

  defp get_campaign_id_for_entity("Fight", id) do
    query_campaign_id("fights", id)
  end

  defp get_campaign_id_for_entity("User", _id) do
    # Users don't belong to campaigns
    nil
  end

  defp get_campaign_id_for_entity(_, _), do: nil

  defp query_campaign_id(table, id) when is_binary(id) do
    query = "SELECT campaign_id FROM #{table} WHERE id = $1"

    case Repo.query(query, [Ecto.UUID.dump!(id)]) do
      {:ok, %{rows: [[campaign_id]]}} ->
        case campaign_id do
          <<_::binary-size(16)>> -> Ecto.UUID.load!(campaign_id)
          other -> other
        end

      _ ->
        nil
    end
  end

  defp query_campaign_id(_, _), do: nil

  @doc """
  Deletes an image attachment for an entity.
  Removes both the attachment and blob records.
  """
  def delete_image(record_type, record_id) do
    query =
      from a in Attachment,
        where:
          a.record_type == ^record_type and
            a.record_id == ^record_id and
            a.name == "image",
        preload: :blob

    case Repo.one(query) do
      nil ->
        {:ok, :no_image}

      attachment ->
        Multi.new()
        |> Multi.delete(:attachment, attachment)
        |> Multi.delete(:blob, attachment.blob)
        |> Repo.transaction()
        |> case do
          {:ok, _} -> {:ok, :deleted}
          {:error, _, changeset, _} -> {:error, changeset}
        end
    end
  end

  # Generate a simple checksum for the blob key
  # Rails uses MD5, we'll do the same for compatibility
  defp generate_checksum(key) do
    :crypto.hash(:md5, key)
    |> Base.encode64()
  end
end
