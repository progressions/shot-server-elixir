defmodule ShotElixir.Services.Notion.Images do
  @moduledoc """
  Image handling helpers for Notion pages.

  - Locate image blocks (with pagination)
  - Attach local images to Notion pages
  - Download and attach Notion images to local characters with SSRF safeguards
  """

  require Logger

  alias ShotElixir.Characters.Character
  alias ShotElixir.Services.Notion.Config
  alias ShotElixir.Services.NotionClient

  @trusted_image_domains [
    ~r/^prod-files-secure\.s3\.us-west-2\.amazonaws\.com$/,
    ~r/^s3\.us-west-2\.amazonaws\.com$/,
    ~r/^.*\.notion\.so$/,
    ~r/^.*\.notion-static\.com$/,
    ~r/^images\.unsplash\.com$/,
    ~r/^.*\.cloudfront\.net$/
  ]

  # ---------------------------------------------------------------------------
  # Lookup
  # ---------------------------------------------------------------------------

  def find_image_block(page, opts \\ []) do
    client = Config.client(opts)
    find_image_block_paginated(page["id"], nil, client)
  end

  defp find_image_block_paginated(page_id, start_cursor, client) do
    response = client.get_block_children(page_id, %{start_cursor: start_cursor})
    results = response["results"] || []

    case Enum.find(results, fn block -> block["type"] == "image" end) do
      nil ->
        if response["has_more"] do
          find_image_block_paginated(page_id, response["next_cursor"], client)
        else
          nil
        end

      image_block ->
        image_block
    end
  end

  # ---------------------------------------------------------------------------
  # Push image to Notion
  # ---------------------------------------------------------------------------

  def add_image_to_notion(%{image_url: nil}), do: nil
  def add_image_to_notion(%{image_url: ""}), do: nil
  def add_image_to_notion(%{notion_page_id: nil}), do: nil

  def add_image_to_notion(%{image_url: url, notion_page_id: page_id}) do
    child = %{
      "object" => "block",
      "type" => "image",
      "image" => %{
        "type" => "external",
        "external" => %{"url" => url}
      }
    }

    NotionClient.append_block_children(page_id, [child])
  rescue
    error ->
      Logger.warning("Failed to add image to Notion: #{Exception.message(error)}")
      nil
  end

  # Fallback for entities without image_url field (e.g., Juncture)
  def add_image_to_notion(_entity), do: nil

  # ---------------------------------------------------------------------------
  # Pull image from Notion and attach locally
  # ---------------------------------------------------------------------------

  def add_image(page, %Character{} = character) do
    existing_image_url = ShotElixir.ActiveStorage.get_image_url("Character", character.id)

    if existing_image_url do
      {:ok, :skipped_existing_image}
    else
      case find_image_block(page) do
        nil ->
          {:ok, :no_image_block}

        image_block ->
          {image_url, is_notion_file} = extract_image_url_with_type(image_block)

          cond do
            is_nil(image_url) ->
              {:ok, :no_image_url}

            is_notion_file ->
              Logger.warning(
                "Notion file URL detected for character #{character.id}. " <>
                  "Download must be immediate as these URLs expire after ~1 hour."
              )

              download_and_attach_image(image_url, character)

            true ->
              download_and_attach_image(image_url, character)
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp extract_image_url_with_type(%{"type" => "image", "image" => image_data}) do
    case image_data do
      %{"type" => "external", "external" => %{"url" => url}} -> {url, false}
      %{"type" => "file", "file" => %{"url" => url}} -> {url, true}
      _ -> {nil, false}
    end
  end

  defp extract_image_url_with_type(_), do: {nil, false}

  defp download_and_attach_image(url, %Character{} = character) do
    case validate_image_url(url) do
      :ok ->
        do_download_with_temp_file(url, character)

      {:error, reason} ->
        Logger.warning("Rejected image URL for SSRF protection: #{inspect(reason)}")
        {:error, {:invalid_url, reason}}
    end
  end

  defp validate_image_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme != "https" -> {:error, :not_https}
      is_nil(uri.host) -> {:error, :no_host}
      not trusted_domain?(uri.host) -> {:error, :untrusted_domain}
      internal_address?(uri.host) -> {:error, :internal_address}
      true -> :ok
    end
  end

  defp validate_image_url(_), do: {:error, :invalid_url}

  defp trusted_domain?(host) do
    Enum.any?(@trusted_image_domains, fn pattern -> Regex.match?(pattern, host) end)
  end

  defp internal_address?(host) do
    host in ["localhost", "127.0.0.1", "0.0.0.0"] or
      String.starts_with?(host, "192.168.") or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "172.16.") or
      String.starts_with?(host, "169.254.") or
      String.ends_with?(host, ".local") or
      String.ends_with?(host, ".internal")
  end

  defp do_download_with_temp_file(url, character) do
    unique_id = :erlang.unique_integer([:positive])
    temp_path = Path.join(System.tmp_dir!(), "notion_image_#{character.id}_#{unique_id}")

    try do
      case File.open(temp_path, [:write, :binary]) do
        {:ok, file} ->
          File.close(file)
          do_download_and_attach(url, temp_path, character)

        {:error, reason} ->
          Logger.error("Failed to create temp file #{temp_path}: #{inspect(reason)}")
          {:error, {:temp_file_creation_failed, reason}}
      end
    after
      cleanup_temp_files(temp_path)
    end
  rescue
    error ->
      Logger.error("Exception downloading Notion image: #{Exception.message(error)}")
      {:error, error}
  end

  defp do_download_and_attach(url, temp_path, character) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
        case File.write(temp_path, body) do
          :ok ->
            extension = url |> URI.parse() |> Map.get(:path, "") |> Path.extname()
            extension = if extension == "", do: ".jpg", else: extension
            final_path = temp_path <> extension

            case File.rename(temp_path, final_path) do
              :ok ->
                Process.put(:notion_final_path, final_path)
                upload_and_attach(final_path, extension, character)

              {:error, reason} ->
                Logger.error("Failed to rename temp file: #{inspect(reason)}")
                {:error, {:rename_failed, reason}}
            end

          {:error, reason} ->
            Logger.error("Failed to write downloaded image to temp file: #{inspect(reason)}")
            {:error, {:write_failed, reason}}
        end

      {:ok, %{status: 200, body: body}} when byte_size(body) == 0 ->
        Logger.warning("Downloaded image is empty (0 bytes)")
        {:error, :empty_download}

      {:ok, %{status: status}} ->
        Logger.warning("Failed to download Notion image, status: #{status}")
        {:error, {:download_failed, status}}

      {:error, reason} ->
        Logger.error("Failed to download Notion image: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upload_and_attach(final_path, extension, character) do
    case ShotElixir.Services.ImagekitService.upload_file(final_path, %{
           folder: "/chi-war-#{Mix.env()}/characters",
           file_name: "#{character.id}#{extension}",
           auto_tag: true,
           max_tags: 10,
           min_confidence: 70
         }) do
      {:ok, upload_result} ->
        case ShotElixir.ActiveStorage.attach_image("Character", character.id, upload_result) do
          {:ok, _attachment} ->
            Logger.info("Successfully attached Notion image to character #{character.id}")
            {:ok, upload_result}

          {:error, reason} ->
            Logger.error("Failed to attach image to character: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to upload Notion image to ImageKit: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cleanup_temp_files(temp_path) do
    File.rm(temp_path)

    case Process.get(:notion_final_path) do
      nil -> :ok
      final_path -> File.rm(final_path)
    end

    Process.delete(:notion_final_path)
  end
end
