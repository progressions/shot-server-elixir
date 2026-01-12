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
      - :auto_tag - Enable AI auto-tagging via Google Vision (default: false)
      - :max_tags - Maximum number of AI tags to generate (default: 10)
      - :min_confidence - Minimum confidence threshold 0-100 (default: 80)

  ## Returns
    - {:ok, response_map} on success with file_id, url, ai_tags, etc.
    - {:error, reason} on failure
  """
  def upload_file(file_path, options \\ %{}) do
    with {:ok, file_content} <- File.read(file_path) do
      if imagekit_disabled?() do
        {:ok, build_stub_upload_result(file_content, file_path, options)}
      else
        case perform_upload(file_content, file_path, options) do
          {:ok, response} ->
            {:ok, parse_upload_response(response)}

          {:error, reason} = error ->
            Logger.error("ImageKit upload failed: #{inspect(reason)}")
            error
        end
      end
    else
      {:error, reason} = error ->
        Logger.error("ImageKit upload failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Uploads a Plug.Upload struct to ImageKit.

  Auto-tagging via Google Vision is enabled by default for all uploads.
  If the extension quota is exceeded, automatically retries without auto-tagging.
  Override with `auto_tag: false` if needed.
  """
  def upload_plug(%Plug.Upload{path: path} = upload, options \\ %{}) do
    default_options = %{auto_tag: true, max_tags: 10, min_confidence: 70}
    options = Map.merge(default_options, Map.put(options, :file_name, upload.filename))

    case upload_file(path, options) do
      {:ok, result} ->
        {:ok, result}

      {:error, :extension_quota_exceeded} ->
        # Retry without auto-tagging when quota is exceeded
        Logger.warning("ImageKit extension quota exceeded, retrying upload without auto-tagging")
        options_without_autotag = Map.put(options, :auto_tag, false)
        upload_file(path, options_without_autotag)

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Uploads a file to ImageKit from a remote URL.

  ## Parameters
    - url: Remote URL of the file to upload
    - options: Map with optional keys:
      - :file_name - Custom filename
      - :folder - Folder path in ImageKit
      - :tags - List of tags
      - :use_unique_file_name - Whether to generate unique filename (default: true)
      - :auto_tag - Enable AI auto-tagging via Google Vision (default: false)
      - :max_tags - Maximum number of AI tags to generate (default: 10)
      - :min_confidence - Minimum confidence threshold 0-100 (default: 80)

  ## Returns
    - {:ok, response_map} on success with file_id, url, ai_tags, etc.
    - {:error, reason} on failure
  """
  def upload_from_url(url, options \\ %{}) do
    file_name = options[:file_name] || file_name_from_url(url)
    folder = options[:folder] || build_folder_path()

    if imagekit_disabled?() do
      return_stub_upload(file_name, folder)
    else
      # Build multipart form data
      multipart_data = [
        {"file", url},
        {"fileName", file_name},
        {"folder", folder},
        {"useUniqueFileName", to_string(Map.get(options, :use_unique_file_name, true))}
      ]

      # Add tags if provided
      multipart_data =
        if options[:tags] && length(options[:tags]) > 0 do
          multipart_data ++ [{"tags", Enum.join(options[:tags], ",")}]
        else
          multipart_data
        end

      # Add extensions for AI auto-tagging if enabled
      multipart_data = maybe_add_extensions(multipart_data, options)

      # Build auth headers for form upload
      auth_token = Base.encode64("#{private_key()}:")

      headers = [
        {"Authorization", "Basic #{auth_token}"}
      ]

      case Req.post(@upload_url, form: multipart_data, headers: headers) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, parse_upload_response(response)}

        {:ok, %{status: status, body: body}} ->
          Logger.error("ImageKit upload from URL failed with status #{status}: #{inspect(body)}")
          {:error, "Upload failed with status #{status}"}

        {:error, reason} = error ->
          Logger.error("ImageKit upload from URL request failed: #{inspect(reason)}")
          error
      end
    end
  end

  @doc """
  Deletes a file from ImageKit by file ID.
  """
  def delete_file(file_id) when is_binary(file_id) do
    if imagekit_disabled?() do
      {:ok, :deleted}
    else
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
    if imagekit_disabled?() do
      file_name = Path.basename(source_file_path)
      folder = destination_folder || build_folder_path()
      return_stub_upload(file_name, folder)
    else
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
    if imagekit_disabled?() do
      {:ok, file_ids}
    else
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
    if imagekit_disabled?() do
      {:ok,
       %{
         file_id: file_id,
         name: nil,
         file_path: nil,
         url: nil,
         thumbnail_url: nil,
         file_type: nil,
         mime: nil,
         size: 0,
         width: nil,
         height: nil,
         created_at: nil,
         updated_at: nil,
         tags: [],
         metadata: %{}
       }}
    else
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

    # Add extensions for AI auto-tagging if enabled
    multipart_data = maybe_add_extensions(multipart_data, options)

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

        # Check for extension quota exceeded error
        if extension_quota_exceeded?(body) do
          {:error, :extension_quota_exceeded}
        else
          {:error, "Upload failed with status #{status}"}
        end

      {:error, reason} = error ->
        Logger.error("ImageKit upload request failed: #{inspect(reason)}")
        error
    end
  end

  defp return_stub_upload(file_name, folder) do
    {:ok, build_stub_upload_result("", file_name, folder)}
  end

  defp build_stub_upload_result(file_content, file_path, options) when is_map(options) do
    file_name = options[:file_name] || Path.basename(file_path)
    folder = options[:folder] || build_folder_path()
    build_stub_upload_result(file_content, file_name, folder)
  end

  defp build_stub_upload_result(file_content, file_name, folder) do
    name = Path.join(folder, file_name)
    url = build_stub_url(name)
    file_type = file_type_from_name(file_name)

    %{
      file_id: "test_#{System.unique_integer([:positive])}",
      name: name,
      url: url,
      thumbnail_url: nil,
      file_type: file_type,
      size: byte_size(file_content),
      width: nil,
      height: nil,
      ai_tags: [],
      metadata: %{"fileType" => file_type}
    }
  end

  defp build_stub_url(name) do
    endpoint = url_endpoint() || ""
    endpoint = String.trim_trailing(endpoint, "/")
    path = String.trim_leading(name, "/")

    if endpoint == "" do
      path
    else
      "#{endpoint}/#{path}"
    end
  end

  defp file_name_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> case do
      nil -> "image.jpg"
      "" -> "image.jpg"
      path -> Path.basename(path)
    end
  end

  defp file_type_from_name(file_name) do
    case Path.extname(file_name) do
      "" -> "jpg"
      ext -> String.trim_leading(ext, ".")
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
      ai_tags: parse_ai_tags(response["AITags"]),
      metadata: response
    }
  end

  defp parse_ai_tags(nil), do: []

  defp parse_ai_tags(ai_tags) when is_list(ai_tags) do
    Enum.map(ai_tags, fn tag ->
      %{
        name: tag["name"],
        confidence: tag["confidence"],
        source: tag["source"]
      }
    end)
  end

  defp parse_ai_tags(_), do: []

  defp maybe_add_extensions(multipart_data, options) do
    if options[:auto_tag] do
      max_tags = Map.get(options, :max_tags, 10)
      min_confidence = Map.get(options, :min_confidence, 80)

      extensions = [
        %{
          "name" => "google-auto-tagging",
          "maxTags" => max_tags,
          "minConfidence" => min_confidence
        }
      ]

      multipart_data ++ [{"extensions", Jason.encode!(extensions)}]
    else
      multipart_data
    end
  end

  defp extension_quota_exceeded?(body) when is_map(body) do
    message = body["message"] || ""

    String.contains?(String.downcase(message), "extensions") and
      (String.contains?(String.downcase(message), "quota") or
         String.contains?(String.downcase(message), "exceeded") or
         String.contains?(String.downcase(message), "limit"))
  end

  defp extension_quota_exceeded?(_), do: false

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

  @doc """
  Returns true when ImageKit network calls should be skipped.

  Checks `IMAGEKIT_DISABLED` or the `:imagekit` config.
  """
  def imagekit_disabled? do
    case System.get_env("IMAGEKIT_DISABLED") do
      nil ->
        config()[:disabled] == true

      value ->
        value = String.downcase(value)
        value in ["1", "true", "yes", "on"]
    end
  end
end
