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
    base64_file = Base.encode64(file_content)

    body = %{
      "file" => base64_file,
      "fileName" => options[:file_name] || Path.basename(file_path),
      "folder" => options[:folder] || build_folder_path(),
      "tags" => options[:tags] || [],
      "useUniqueFileName" => Map.get(options, :use_unique_file_name, true)
    }

    headers = build_auth_headers()

    case Req.post(@upload_url, json: body, headers: headers) do
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

  defp url_endpoint do
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