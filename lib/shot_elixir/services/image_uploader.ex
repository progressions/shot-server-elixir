defmodule ShotElixir.Services.ImageUploader do
  @moduledoc """
  Shared service for downloading images from URLs and uploading them to ImageKit.

  This module consolidates the common image handling logic used by both
  ImageKitImporter and AiService, providing a single source of truth for:
  - Downloading images from URLs with proper error handling
  - Uploading images to ImageKit with consistent folder structure
  - Entity type pluralization for folder paths

  ## Usage

      # Download an image to a temporary file
      {:ok, temp_path} = ImageUploader.download_image("https://example.com/image.jpg")

      # Upload a file to ImageKit
      {:ok, upload_result} = ImageUploader.upload_to_imagekit(temp_path, "Character", character_id)

      # Clean up temp file after use
      File.rm(temp_path)
  """

  require Logger

  alias ShotElixir.Services.ImagekitService

  @max_redirects 5
  @default_timeout 30_000

  @doc """
  Downloads an image from a URL to a temporary file.

  Handles redirects and various HTTP error conditions gracefully.

  ## Parameters
    - url: The URL to download the image from

  ## Returns
    - `{:ok, temp_path}` on success with the path to the temporary file
    - `{:error, reason}` on failure

  ## Examples

      iex> ImageUploader.download_image("https://example.com/image.jpg")
      {:ok, "/tmp/image_download_1234567890.jpg"}

      iex> ImageUploader.download_image("https://invalid.url/404.jpg")
      {:error, "HTTP request failed with status 404"}
  """
  def download_image(url) do
    Logger.debug("[ImageUploader] Downloading image from: #{url}")

    if ImagekitService.imagekit_disabled?() and imagekit_url?(url) do
      create_stub_file(url)
    else
      case Req.get(url,
             redirect: true,
             max_redirects: @max_redirects,
             receive_timeout: @default_timeout
           ) do
        {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
          extension = extract_extension(url)

          temp_path =
            Path.join(
              System.tmp_dir!(),
              "image_download_#{:os.system_time(:millisecond)}#{extension}"
            )

          case File.write(temp_path, body) do
            :ok ->
              Logger.debug("[ImageUploader] Image downloaded to: #{temp_path}")
              {:ok, temp_path}

            {:error, reason} ->
              {:error, "Failed to write temp file: #{inspect(reason)}"}
          end

        {:ok, %{status: 200, body: body}} ->
          {:error, "Empty response body: #{inspect(body)}"}

        {:ok, %{status: status}} ->
          {:error, "HTTP request failed with status #{status}"}

        {:error, %Req.TransportError{reason: reason}} ->
          {:error, "Transport error: #{inspect(reason)}"}

        {:error, reason} ->
          {:error, "Failed to download image: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Uploads a file to ImageKit under the appropriate entity folder.

  ## Parameters
    - file_path: Path to the file to upload
    - entity_type: The entity type (e.g., "Character", "Weapon")
    - entity_id: The entity's UUID

  ## Returns
    - `{:ok, upload_result}` on success with ImageKit upload response
    - `{:error, reason}` on failure

  ## Examples

      iex> ImageUploader.upload_to_imagekit("/tmp/image.jpg", "Character", "abc-123")
      {:ok, %{url: "https://ik.imagekit.io/...", ...}}
  """
  def upload_to_imagekit(file_path, entity_type, entity_id) do
    Logger.debug("[ImageUploader] Uploading to ImageKit for #{entity_type}:#{entity_id}")

    plural_folder = pluralize_entity_type(String.downcase(entity_type))

    options = %{
      file_name:
        "#{String.downcase(entity_type)}_#{entity_id}_#{:os.system_time(:millisecond)}.jpg",
      folder: "/chi-war-#{environment()}/#{plural_folder}",
      auto_tag: true,
      max_tags: 10,
      min_confidence: 70
    }

    ImagekitService.upload_file(file_path, options)
  end

  @doc """
  Downloads an image and uploads it to ImageKit in one operation.

  Handles temporary file cleanup automatically.

  ## Parameters
    - url: The URL to download the image from
    - entity_type: The entity type (e.g., "Character", "Weapon")
    - entity_id: The entity's UUID

  ## Returns
    - `{:ok, upload_result}` on success with ImageKit upload response
    - `{:error, reason}` on failure
  """
  def download_and_upload(url, entity_type, entity_id) do
    with {:ok, temp_path} <- download_image(url),
         result <- do_upload_and_cleanup(temp_path, entity_type, entity_id) do
      result
    end
  end

  defp do_upload_and_cleanup(temp_path, entity_type, entity_id) do
    try do
      upload_to_imagekit(temp_path, entity_type, entity_id)
    after
      File.rm(temp_path)
    end
  end

  @doc """
  Pluralizes an entity type name for use in folder paths.

  ## Examples

      iex> ImageUploader.pluralize_entity_type("character")
      "characters"

      iex> ImageUploader.pluralize_entity_type("party")
      "parties"
  """
  def pluralize_entity_type("character"), do: "characters"
  def pluralize_entity_type("weapon"), do: "weapons"
  def pluralize_entity_type("schtick"), do: "schticks"
  def pluralize_entity_type("faction"), do: "factions"
  def pluralize_entity_type("juncture"), do: "junctures"
  def pluralize_entity_type("site"), do: "sites"
  def pluralize_entity_type("party"), do: "parties"
  def pluralize_entity_type("vehicle"), do: "vehicles"
  def pluralize_entity_type("campaign"), do: "campaigns"
  def pluralize_entity_type("user"), do: "users"
  def pluralize_entity_type("fight"), do: "fights"
  def pluralize_entity_type(type), do: "#{type}s"

  # Private functions

  defp extract_extension(url) do
    uri = URI.parse(url)
    path = uri.path || ""

    case Path.extname(path) do
      "" -> ".jpg"
      ext -> ext
    end
  end

  defp imagekit_url?(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        String.contains?(host, "ik.imagekit.io")

      _ ->
        false
    end
  end

  defp create_stub_file(url) do
    extension = extract_extension(url)

    temp_path =
      Path.join(System.tmp_dir!(), "image_download_#{:os.system_time(:millisecond)}#{extension}")

    case File.write(temp_path, "") do
      :ok ->
        Logger.debug("[ImageUploader] ImageKit disabled, stub file: #{temp_path}")
        {:ok, temp_path}

      {:error, reason} ->
        {:error, "Failed to write temp file: #{inspect(reason)}"}
    end
  end

  defp environment do
    case Application.get_env(:shot_elixir, :environment) do
      nil ->
        raise "[ImageUploader] :environment not set in :shot_elixir config. Please set :environment in your config files."

      env when is_atom(env) ->
        to_string(env)

      env when is_binary(env) ->
        env
    end
  end
end
