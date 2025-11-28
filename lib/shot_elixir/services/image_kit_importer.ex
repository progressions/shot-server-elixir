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
  alias ShotElixir.Services.ImagekitService

  @max_redirects 5
  @default_timeout 30_000

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

    case download_image(source_url) do
      {:ok, temp_file} ->
        try do
          with {:ok, upload_result} <-
                 upload_to_imagekit(temp_file, attachable_type, attachable_id),
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

  defp download_image(url) do
    Logger.debug("[ImageKitImporter] Downloading image from: #{url}")

    # Use Req with redirect handling (similar to Rails Net::HTTP with follow_redirects)
    case Req.get(url,
           redirect: true,
           max_redirects: @max_redirects,
           receive_timeout: @default_timeout
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
        # Create temp file with appropriate extension
        extension = extract_extension(url)

        temp_path =
          Path.join(
            System.tmp_dir!(),
            "imagekit_import_#{:os.system_time(:millisecond)}#{extension}"
          )

        case File.write(temp_path, body) do
          :ok ->
            Logger.debug("[ImageKitImporter] Image downloaded to: #{temp_path}")
            {:ok, temp_path}

          {:error, reason} ->
            {:error, "Failed to write temp file: #{inspect(reason)}"}
        end

      {:ok, %{status: 200, body: body}} ->
        {:error, "Empty response body: #{inspect(body)}"}

      {:ok, %{status: status}} ->
        {:error, "HTTP request failed with status #{status}"}

      {:error, %Req.TransportError{reason: reason}} ->
        # Handle SSL or connection errors gracefully
        {:error, "Transport error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Failed to download image: #{inspect(reason)}"}
    end
  end

  defp upload_to_imagekit(file_path, entity_type, entity_id) do
    Logger.debug("[ImageKitImporter] Uploading to ImageKit for #{entity_type}:#{entity_id}")

    plural_folder = pluralize_entity_type(String.downcase(entity_type))

    options = %{
      file_name:
        "#{String.downcase(entity_type)}_#{entity_id}_#{:os.system_time(:millisecond)}.jpg",
      folder: "/chi-war-#{environment()}/#{plural_folder}"
    }

    ImagekitService.upload_file(file_path, options)
  end

  defp extract_entity_info(entity) do
    # Get the module name and extract the entity type
    module = entity.__struct__
    type = module |> Module.split() |> List.last()
    {type, entity.id}
  end

  defp extract_extension(url) do
    uri = URI.parse(url)
    path = uri.path || ""

    case Path.extname(path) do
      "" -> ".jpg"
      ext -> ext
    end
  end

  defp pluralize_entity_type("character"), do: "characters"
  defp pluralize_entity_type("weapon"), do: "weapons"
  defp pluralize_entity_type("schtick"), do: "schticks"
  defp pluralize_entity_type("faction"), do: "factions"
  defp pluralize_entity_type("juncture"), do: "junctures"
  defp pluralize_entity_type("site"), do: "sites"
  defp pluralize_entity_type("party"), do: "parties"
  defp pluralize_entity_type("vehicle"), do: "vehicles"
  defp pluralize_entity_type("campaign"), do: "campaigns"
  defp pluralize_entity_type("user"), do: "users"
  defp pluralize_entity_type("fight"), do: "fights"
  defp pluralize_entity_type(type), do: "#{type}s"

  defp environment do
    case Application.get_env(:shot_elixir, :environment) do
      nil -> Mix.env() |> to_string()
      env when is_atom(env) -> to_string(env)
      env when is_binary(env) -> env
    end
  end
end
