defmodule ShotElixir.Repo.Migrations.PopulateMediaImagesFromActiveStorage do
  use Ecto.Migration

  import Ecto.Query

  @doc """
  Populates media_images table from existing ActiveStorage attachments.
  This creates records for all uploaded images with source = "upload" and status = "attached".
  """
  def up do
    # Get all attachments with their blobs
    attachments_query = """
    SELECT
      a.id,
      a.name,
      a.record_type,
      a.record_id,
      a.blob_id,
      a.created_at as attachment_created_at,
      b.id as blob_id,
      b.key,
      b.filename,
      b.content_type,
      b.metadata,
      b.byte_size,
      b.created_at as blob_created_at
    FROM active_storage_attachments a
    JOIN active_storage_blobs b ON a.blob_id = b.id
    WHERE a.name = 'image'
    """

    {:ok, result} = repo().query(attachments_query, [])
    columns = Enum.map(result.columns, &String.to_atom/1)

    # Process each attachment
    Enum.each(result.rows, fn row ->
      attachment = Enum.zip(columns, row) |> Map.new()

      # Get campaign_id based on entity type
      campaign_id = get_campaign_id(attachment.record_type, attachment.record_id)

      if campaign_id do
        # Parse blob metadata for ImageKit info
        metadata = parse_metadata(attachment.metadata)

        imagekit_file_id = metadata["imagekit_file_id"]
        imagekit_url = metadata["imagekit_url"] || metadata["url"]
        imagekit_file_path = metadata["imagekit_file_path"] || attachment.key

        # Build ImageKit URL if not in metadata
        imagekit_url = imagekit_url || build_imagekit_url(attachment.key)

        # Only create if we have required imagekit data
        if imagekit_file_id && imagekit_url do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          insert_query = """
          INSERT INTO media_images (
            id, campaign_id, source, entity_type, entity_id, status,
            active_storage_blob_id, imagekit_file_id, imagekit_url, imagekit_file_path,
            filename, content_type, byte_size, inserted_at, updated_at
          ) VALUES (
            gen_random_uuid(), $1, 'upload', $2, $3, 'attached',
            $4, $5, $6, $7,
            $8, $9, $10, $11, $12
          )
          ON CONFLICT (imagekit_file_id) DO NOTHING
          """

          repo().query(insert_query, [
            campaign_id,
            attachment.record_type,
            attachment.record_id,
            attachment.blob_id,
            imagekit_file_id,
            imagekit_url,
            imagekit_file_path,
            attachment.filename,
            attachment.content_type,
            attachment.byte_size,
            now,
            now
          ])
        end
      end
    end)
  end

  def down do
    # Remove all uploaded images (keep AI-generated ones if any exist)
    execute("DELETE FROM media_images WHERE source = 'upload'")
  end

  # Get campaign_id for each entity type
  defp get_campaign_id("Character", record_id) do
    query_campaign_id("characters", record_id)
  end

  defp get_campaign_id("Vehicle", record_id) do
    query_campaign_id("vehicles", record_id)
  end

  defp get_campaign_id("Weapon", record_id) do
    query_campaign_id("weapons", record_id)
  end

  defp get_campaign_id("Schtick", record_id) do
    query_campaign_id("schticks", record_id)
  end

  defp get_campaign_id("Site", record_id) do
    query_campaign_id("sites", record_id)
  end

  defp get_campaign_id("Faction", record_id) do
    query_campaign_id("factions", record_id)
  end

  defp get_campaign_id("Party", record_id) do
    query_campaign_id("parties", record_id)
  end

  defp get_campaign_id("User", _record_id) do
    # Users don't belong to campaigns - skip these
    nil
  end

  defp get_campaign_id("Fight", record_id) do
    query_campaign_id("fights", record_id)
  end

  defp get_campaign_id(_, _), do: nil

  defp query_campaign_id(table, record_id) do
    query = "SELECT campaign_id FROM #{table} WHERE id = $1"

    case repo().query(query, [record_id]) do
      {:ok, %{rows: [[campaign_id]]}} -> campaign_id
      _ -> nil
    end
  end

  defp parse_metadata(nil), do: %{}
  defp parse_metadata(""), do: %{}

  defp parse_metadata(metadata) when is_binary(metadata) do
    case Jason.decode(metadata) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  defp parse_metadata(metadata) when is_map(metadata), do: metadata
  defp parse_metadata(_), do: %{}

  defp build_imagekit_url(key) when is_binary(key) do
    # Use the same endpoint as ImagekitService
    endpoint = System.get_env("IMAGEKIT_URL_ENDPOINT") || "https://ik.imagekit.io/nvqgwnjgv"
    endpoint = String.trim_trailing(endpoint, "/")
    key = String.trim_leading(key, "/")
    "#{endpoint}/#{key}"
  end

  defp build_imagekit_url(_), do: nil
end
