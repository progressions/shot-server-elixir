defmodule ShotElixir.Services.ImageKitImporter do
  @moduledoc """
  Service for downloading images from URLs and attaching them to entities.

  This service mirrors the Rails ImageKitImporter functionality:
  1. Downloads an image from a source URL (typically an ImageKit URL)
  2. Uploads the image to ImageKit under the entity's folder
  3. Creates ActiveStorage blob and attachment records

  ## Usage

      # Copy an image from one entity to another
      ImageKitImporter.call(
        source_url: "https://ik.imagekit.io/nvqgwnjgv/chi-war-dev/characters/image.jpg",
        attachable_type: "Character",
        attachable_id: character.id
      )

      # Convenience function using entity struct
      ImageKitImporter.import_for(source_url: source_url, entity: character)
  """

  require Logger

  alias ShotElixir.ActiveStorage
  alias ShotElixir.Services.ImageUploader

  @doc """
  Downloads an image from a URL and attaches it to an entity.

  ## Options
    - `:source_url` - Required. The URL to download the image from.
    - `:attachable_type` - Required. The entity type ("Character", "Weapon", etc.)
    - `:attachable_id` - Required. The entity's UUID

  ## Returns
    - `{:ok, attachment}` on success
    - `{:error, reason}` on failure
  """
  def call(opts) when is_list(opts) do
    source_url = Keyword.fetch!(opts, :source_url)
    attachable_type = Keyword.fetch!(opts, :attachable_type)
    attachable_id = Keyword.fetch!(opts, :attachable_id)

    import_image(source_url, attachable_type, attachable_id)
  end

  @doc """
  Convenience function that extracts type and ID from an entity struct.

  ## Options
    - `:source_url` - Required. The URL to download the image from.
    - `:entity` - Required. The entity struct to attach the image to.

  ## Examples

      ImageKitImporter.import_for(source_url: url, entity: character)
      ImageKitImporter.import_for(source_url: url, entity: weapon)
  """
  def import_for(opts) when is_list(opts) do
    source_url = Keyword.fetch!(opts, :source_url)
    entity = Keyword.fetch!(opts, :entity)

    {attachable_type, attachable_id} = extract_entity_info(entity)
    import_image(source_url, attachable_type, attachable_id)
  end

  @doc """
  Copies an image from a source entity to a target entity.

  ## Parameters
    - `source_entity` - The entity to copy the image from
    - `target_entity` - The entity to attach the image to

  ## Returns
    - `{:ok, attachment}` on success
    - `{:error, :no_image}` if source has no image
    - `{:error, reason}` on failure
  """
  def copy_image(source_entity, target_entity) do
    {source_type, source_id} = extract_entity_info(source_entity)

    case ActiveStorage.get_image_url(source_type, source_id) do
      nil ->
        {:error, :no_image}

      source_url ->
        import_for(source_url: source_url, entity: target_entity)
    end
  end

  # Private functions

  defp import_image(source_url, attachable_type, attachable_id) do
    Logger.info(
      "[ImageKitImporter] Importing image for #{attachable_type}:#{attachable_id} from #{source_url}"
    )

    case ImageUploader.download_image(source_url) do
      {:ok, temp_file} ->
        try do
          with {:ok, upload_result} <-
                 ImageUploader.upload_to_imagekit(temp_file, attachable_type, attachable_id),
               {:ok, attachment} <-
                 ActiveStorage.attach_image(attachable_type, attachable_id, upload_result) do
            Logger.info(
              "[ImageKitImporter] Successfully imported image for #{attachable_type}:#{attachable_id}"
            )

            {:ok, attachment}
          else
            {:error, reason} = error ->
              Logger.error("[ImageKitImporter] Failed to import image: #{inspect(reason)}")
              error
          end
        after
          File.rm(temp_file)
        end

      error ->
        error
    end
  end

  defp extract_entity_info(entity) do
    # Get the module name and extract the entity type
    module = entity.__struct__
    type = module |> Module.split() |> List.last()
    {type, entity.id}
  end
end
