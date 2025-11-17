defmodule ShotElixir.ActiveStorage do
  @moduledoc """
  Context for reading ActiveStorage attachments created by Rails.
  Provides read-only access to image URLs and metadata.
  """

  import Ecto.Query
  alias ShotElixir.Repo
  alias ShotElixir.ActiveStorage.{Attachment, Blob}
  alias ShotElixir.Services.ImagekitService

  @doc """
  Gets the image URL for a record by querying ActiveStorage tables.
  Returns nil if no image is attached.

  ## Examples

      iex> get_image_url("Character", character_id)
      "https://ik.imagekit.io/nvqgwnjgv/chi-war-dev/characters/image.jpg"

      iex> get_image_url("Character", character_with_no_image_id)
      nil
  """
  def get_image_url(record_type, record_id) when is_binary(record_type) and is_binary(record_id) do
    query =
      from a in Attachment,
        join: b in Blob,
        on: a.blob_id == b.id,
        where: a.record_type == ^record_type and a.record_id == ^record_id and a.name == "image",
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
  def get_image_urls_for_records(record_type, record_ids) when is_binary(record_type) and is_list(record_ids) do
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
end
