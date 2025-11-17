defmodule ShotElixir.Services.AiService do
  @moduledoc """
  Service for AI-powered operations like image generation and attachment.
  Provides functionality to download and attach images from URLs to entities.
  """

  require Logger
  alias ShotElixir.ActiveStorage
  alias ShotElixir.Services.ImagekitService

  @doc """
  Downloads an image from a URL and attaches it to an entity.

  ## Parameters
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity
    - image_url: URL to download the image from

  ## Returns
    - {:ok, attachment} on success
    - {:error, reason} on failure

  ## Examples
      iex> attach_image_from_url("Character", character_id, "https://example.com/image.jpg")
      {:ok, %Attachment{}}
  """
  def attach_image_from_url(entity_type, entity_id, image_url) when is_binary(image_url) do
    with {:ok, temp_file} <- download_image(image_url),
         {:ok, upload_result} <- upload_to_imagekit(temp_file, entity_type, entity_id),
         {:ok, attachment} <- ActiveStorage.attach_image(entity_type, entity_id, upload_result) do
      # Clean up temp file
      File.rm(temp_file)
      {:ok, attachment}
    else
      {:error, reason} = error ->
        Logger.error("Failed to attach image from URL: #{inspect(reason)}")
        error
    end
  end

  # Downloads image from URL to a temporary file
  defp download_image(url) do
    Logger.info("Downloading image from URL: #{url}")

    case Req.get(url, [redirect: true]) do
      {:ok, %{status: 200, body: body}} ->
        # Create temp file
        temp_path = Path.join(System.tmp_dir!(), "ai_image_#{:os.system_time(:millisecond)}.jpg")

        case File.write(temp_path, body) do
          :ok ->
            Logger.info("Image downloaded to: #{temp_path}")
            {:ok, temp_path}

          {:error, reason} ->
            {:error, "Failed to write temp file: #{inspect(reason)}"}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP request failed with status #{status}"}

      {:error, reason} ->
        {:error, "Failed to download image: #{inspect(reason)}"}
    end
  end

  # Uploads the downloaded image to ImageKit
  defp upload_to_imagekit(file_path, entity_type, entity_id) do
    Logger.info("Uploading image to ImageKit for #{entity_type}:#{entity_id}")

    options = %{
      file_name: "#{String.downcase(entity_type)}_#{entity_id}_#{:os.system_time(:millisecond)}.jpg",
      folder: "/chi-war-#{Mix.env()}/#{String.downcase(entity_type)}s"
    }

    ImagekitService.upload_file(file_path, options)
  end
end
