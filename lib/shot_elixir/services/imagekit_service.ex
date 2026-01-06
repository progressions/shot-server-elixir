defmodule ShotElixir.Services.ImagekitService do
  @moduledoc """
  Service for interacting with ImageKit.io API for image storage and transformation.
  Provides upload, deletion, and URL generation functionality compatible with Rails implementation.
  """

  require Logger

  @base_url "https://api.imagekit.io/v1"
  @upload_url "https://upload.imagekit.io/api/v1/files/upload"

  @doc """
  Uploads a file to ImageKit.

  ## Parameters
    - file_path: Path to the file to upload
    - options: Map with optional keys:
      - :file_name - Custom filename
      - :folder - Folder path in ImageKit
      - :tags - List of tags
      - :use_unique_file_name - Whether to generate unique filename (default: true)

  ## Returns
    - {:ok, response_map} on success with file_id, url, etc.
    - {:error, reason} on failure
  """
  def upload_file(file_path, options \\ %{}) do
    with {:ok, file_content} <- File.read(file_path),
         {:ok, response} <- perform_upload(file_content, file_path, options) do
      {:ok, parse_upload_response(response)}
    else
      {:error, reason} = error ->
        Logger.error("ImageKit upload failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Uploads a Plug.Upload struct to ImageKit.
  """
  def upload_plug(%Plug.Upload{path: path} = upload, options \\ %{}) do
    options = Map.put(options, :file_name, upload.filename)
    upload_file(path, options)
  end

  @doc """
  Deletes a file from ImageKit by file ID.
  """
  def delete_file(file_id) when is_binary(file_id) do
    url = "#{@base_url}/files/#{file_id}"
    headers = build_auth_headers()

    case Req.delete(url, headers: headers) do
      {:ok, %{status: 204}} ->
        {:ok, :deleted}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ImageKit delete failed with status #{status}: #{inspect(body)}")
        {:error, "Delete failed with status #{status}"}

      {:error, reason} = error ->
        Logger.error("ImageKit delete request failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Copies a file within ImageKit.

  ## Parameters
    - source_file_path: Full path to the source file in ImageKit
    - destination_folder: Folder path to copy to

  ## Returns
    - {:ok, response_map} on success with new file_id, url, etc.
    - {:error, reason} on failure
  """
  def copy_file(source_file_path, destination_folder) do
    url = "#{@base_url}/files/copy"
    headers = build_auth_headers()

    body =
      Jason.encode!(%{
        "sourceFilePath" => source_file_path,
        "destinationPath" => destination_folder,
        "includeFileVersions" => false
      })

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: status, body: response}} when status in [200, 201] ->
        {:ok, parse_upload_response(response)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ImageKit copy failed with status #{status}: #{inspect(body)}")
        {:error, "Copy failed with status #{status}"}

      {:error, reason} = error ->
        Logger.error("ImageKit copy request failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Deletes multiple files from ImageKit by file IDs.

  ## Parameters
    - file_ids: List of ImageKit file IDs to delete

  ## Returns
    - {:ok, deleted_ids} on success with list of deleted file IDs
    - {:error, reason} on failure (if any file is not found, all fail)
  """
  def bulk_delete_files(file_ids) when is_list(file_ids) do
    url = "#{@base_url}/files/batch/deleteByFileIds"
    headers = build_auth_headers()

    body = Jason.encode!(%{"fileIds" => file_ids})

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response["successfullyDeletedFileIds"] || []}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ImageKit bulk delete failed with status #{status}: #{inspect(body)}")
        {:error, "Bulk delete failed with status #{status}"}

      {:error, reason} = error ->
        Logger.error("ImageKit bulk delete request failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets file details/metadata from ImageKit.

  ## Parameters
    - file_id: ImageKit file ID

  ## Returns
    - {:ok, details_map} on success with file metadata
    - {:error, reason} on failure
  """
  def get_file_details(file_id) when is_binary(file_id) do
    url = "#{@base_url}/files/#{file_id}/details"
    headers = build_auth_headers()

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_file_details(response)}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ImageKit get details failed with status #{status}: #{inspect(body)}")
        {:error, "Get details failed with status #{status}"}

      {:error, reason} = error ->
        Logger.error("ImageKit get details request failed: #{inspect(reason)}")
        error
    end
  end

  defp parse_file_details(response) do
    %{
      file_id: response["fileId"],
      name: response["name"],
      file_path: response["filePath"],
      url: response["url"],
      thumbnail_url: response["thumbnail"],
      file_type: response["fileType"],
      mime: response["mime"],
      size: response["size"],
      width: response["width"],
      height: response["height"],
      created_at: response["createdAt"],
      updated_at: response["updatedAt"],
      tags: response["tags"] || [],
      metadata: response
    }
  end

  @doc """
  Generates a CDN URL for a file with optional transformations.

  ## Parameters
    - file_name: The file name/path in ImageKit
    - transformations: List of transformation maps

  ## Examples
    generate_url("myimage.jpg", [])
    generate_url("myimage.jpg", [%{height: 300, width: 300}])
  """
  def generate_url(file_name, transformations \\ []) do
    base = url_endpoint()
    transform_string = build_transformation_string(transformations)

    if transform_string == "" do
      "#{base}/#{file_name}"
    else
      "#{base}/tr:#{transform_string}/#{file_name}"
    end
  end

  @doc """
  Generates a URL from stored image data (compatible with Rails implementation).
  """
  def generate_url_from_metadata(%{"name" => name}) do
    generate_url(name)
  end

  def generate_url_from_metadata(_), do: nil

  # Private functions

  defp perform_upload(file_content, file_path, options) do
    # ImageKit accepts either base64 string, binary, or URL
    # Using base64 string for simplicity
    base64_file = Base.encode64(file_content)

    # Build multipart form data
    multipart_data = [
      {"file", base64_file},
      {"fileName", options[:file_name] || Path.basename(file_path)},
      {"folder", options[:folder] || build_folder_path()},
      {"useUniqueFileName", to_string(Map.get(options, :use_unique_file_name, true))}
    ]

    # Add tags if provided
    multipart_data =
      if options[:tags] && length(options[:tags]) > 0 do
        multipart_data ++ [{"tags", Enum.join(options[:tags], ",")}]
      else
        multipart_data
      end

    # Build auth headers for form upload
    auth_token = Base.encode64("#{private_key()}:")

    headers = [
      {"Authorization", "Basic #{auth_token}"}
    ]

    case Req.post(@upload_url, form: multipart_data, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ImageKit upload failed with status #{status}: #{inspect(body)}")
        {:error, "Upload failed with status #{status}"}

      {:error, reason} = error ->
        Logger.error("ImageKit upload request failed: #{inspect(reason)}")
        error
    end
  end

  defp parse_upload_response(response) do
    %{
      file_id: response["fileId"],
      name: response["name"],
      url: response["url"],
      thumbnail_url: response["thumbnailUrl"],
      file_type: response["fileType"],
      size: response["size"],
      width: response["width"],
      height: response["height"],
      metadata: response
    }
  end

  defp build_auth_headers do
    auth_token = Base.encode64("#{private_key()}:")

    [
      {"Authorization", "Basic #{auth_token}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp build_folder_path do
    "/chi-war-#{environment()}"
  end

  defp build_transformation_string([]), do: ""

  defp build_transformation_string(transformations) when is_list(transformations) do
    transformations
    |> Enum.map(&transformation_to_string/1)
    |> Enum.join(",")
  end

  defp transformation_to_string(%{height: h, width: w}) do
    "h-#{h},w-#{w}"
  end

  defp transformation_to_string(%{quality: q}) do
    "q-#{q}"
  end

  defp transformation_to_string(%{format: f}) do
    "f-#{f}"
  end

  defp transformation_to_string(transform) do
    transform
    |> Enum.map(fn {k, v} -> "#{k}-#{v}" end)
    |> Enum.join(",")
  end

  # Configuration helpers

  defp private_key do
    config()[:private_key] ||
      System.get_env("IMAGEKIT_PRIVATE_KEY") ||
      raise "ImageKit private key not configured"
  end

  # Currently unused - kept for potential future use
  # defp public_key do
  #   config()[:public_key] ||
  #     System.get_env("IMAGEKIT_PUBLIC_KEY") ||
  #     raise "ImageKit public key not configured"
  # end

  @doc """
  Returns the configured ImageKit URL endpoint.
  Public function needed by ActiveStorage module for building image URLs.
  """
  def url_endpoint do
    config()[:url_endpoint] ||
      "https://ik.imagekit.io/#{imagekit_id()}/chi-war-#{environment()}"
  end

  defp imagekit_id do
    config()[:id] ||
      System.get_env("IMAGEKIT_ID") ||
      "nvqgwnjgv"
  end

  defp environment do
    config()[:environment] ||
      Application.get_env(:shot_elixir, :environment) ||
      Mix.env() |> to_string()
  end

  defp config do
    Application.get_env(:shot_elixir, :imagekit, [])
  end
end
