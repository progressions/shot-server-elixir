defmodule ShotElixir.Services.NotionService do
  @moduledoc """
  Business logic layer for Notion API integration.
  Handles character synchronization with Notion database.
  """

  require Logger

  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Notion
  alias ShotElixir.Repo

  # Use runtime config to allow token to be added at runtime without validation errors
  defp database_id do
    Application.get_env(:shot_elixir, :notion)[:database_id] ||
      "f6fa27ac-19cd-4b17-b218-55acc6d077be"
  end

  defp factions_database_id do
    Application.get_env(:shot_elixir, :notion)[:factions_database_id] ||
      "0ae94bfa1a754c8fbda28ea50afa5fd5"
  end

  @doc """
  Main sync function - creates or updates character in Notion.
  Environment check performed at worker level.
  """
  def sync_character(%Character{} = character) do
    character = Repo.preload(character, :faction)

    result =
      if character.notion_page_id do
        update_notion_from_character(character)
      else
        create_notion_from_character(character)
      end

    case result do
      {:ok, _} ->
        Characters.update_character(character, %{
          last_synced_to_notion_at: DateTime.utc_now()
        })

      {:error, reason} ->
        Logger.error("Failed to sync character to Notion: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception syncing character to Notion: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Create a new Notion page from character data.
  """
  def create_notion_from_character(%Character{} = character) do
    # Ensure faction is loaded for Notion properties
    character = Repo.preload(character, :faction)
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props = notion_faction_properties(character.faction.name)
        # Only add Faction if we found a matching faction in Notion
        if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
      else
        properties
      end

    Logger.debug("Creating Notion page with database_id: #{database_id()}")

    # Capture payload for logging
    payload = %{
      "parent" => %{"database_id" => database_id()},
      "properties" => properties
    }

    page = NotionClient.create_page(payload)

    Logger.debug("Notion API response received")

    # Check if Notion returned an error response
    case page do
      %{"id" => page_id} when is_binary(page_id) ->
        Logger.debug("Extracted page ID: #{inspect(page_id)}")

        # Log successful sync
        Notion.log_success(character.id, payload, page)

        # Update character with notion_page_id
        case Characters.update_character(character, %{notion_page_id: page_id}) do
          {:ok, updated_character} ->
            Logger.debug(
              "Character updated with notion_page_id: #{inspect(updated_character.notion_page_id)}"
            )

            # Add image if present
            add_image_to_notion(updated_character)
            {:ok, page}

          {:error, changeset} ->
            Logger.error("Failed to update character with notion_page_id")
            {:error, changeset}
        end

      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion API error: #{error_code}")
        # Log error sync
        Notion.log_error(
          character.id,
          payload,
          page,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      _ ->
        Logger.error("Unexpected response from Notion API")
        # Log error sync
        Notion.log_error(character.id, payload, page, "Unexpected response from Notion API")
        {:error, :unexpected_notion_response}
    end
  rescue
    error ->
      # Avoid logging potentially sensitive HTTP request metadata
      Logger.error("Failed to create Notion page: #{Exception.message(error)}")
      # Log error sync (with nil payload since we may not have gotten there)
      Notion.log_error(character.id, %{}, %{}, "Exception: #{Exception.message(error)}")
      {:error, :notion_request_failed}
  end

  @doc """
  Update existing Notion page with character data.
  """
  def update_notion_from_character(%Character{notion_page_id: nil}), do: {:error, :no_page_id}

  def update_notion_from_character(%Character{} = character) do
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props = notion_faction_properties(character.faction.name)
        # Only add Faction if we found a matching faction in Notion
        if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
      else
        properties
      end

    # Capture payload for logging
    payload = %{
      "page_id" => character.notion_page_id,
      "properties" => properties
    }

    response = NotionClient.update_page(character.notion_page_id, properties)

    # Check if Notion returned an error response
    case response do
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion API error on update: #{error_code}")

        Notion.log_error(
          character.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      _ ->
        # Add image if not present in Notion
        page = NotionClient.get_page(character.notion_page_id)
        image = find_image_block(page)

        unless image do
          add_image_to_notion(character)
        end

        # Log successful sync
        Notion.log_success(character.id, payload, response || page)

        {:ok, page}
    end
  rescue
    error ->
      Logger.error("Failed to update Notion page: #{inspect(error)}")
      # Log error sync
      Notion.log_error(
        character.id,
        %{"page_id" => character.notion_page_id},
        %{},
        "Exception: #{inspect(error)}"
      )

      {:error, error}
  end

  @doc """
  Find or create a character from Notion page data.
  """
  def find_or_create_character_from_notion(page, campaign_id) do
    name = get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])

    {:ok, character} = Characters.find_or_create_by_name_and_campaign(name, campaign_id)

    character = Repo.preload(character, :faction)
    attributes = Character.attributes_from_notion(character, page)

    {:ok, character} =
      Characters.update_character(character, Map.put(attributes, :notion_page_id, page["id"]))

    description = get_description(page)

    merged_description =
      Map.merge(
        description,
        character.description || %{},
        fn _k, v1, v2 -> if v2 == "" or is_nil(v2), do: v1, else: v2 end
      )

    {:ok, character} = Characters.update_character(character, %{description: merged_description})

    # Add image if not already present
    add_image(page, character)

    {:ok, character}
  rescue
    error ->
      Logger.error("Failed to find or create character from Notion: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Update character from Notion page data.
  """
  def update_character_from_notion(%Character{notion_page_id: nil}), do: {:error, :no_page_id}

  def update_character_from_notion(%Character{} = character) do
    page = NotionClient.get_page(character.notion_page_id)
    attributes = Character.attributes_from_notion(character, page)

    # Add image if not already present
    add_image(page, character)

    Characters.update_character(character, attributes)
  rescue
    error ->
      Logger.error("Failed to update character from Notion: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Search for Notion pages by name.

  ## Parameters
    * `name` - The name to search for

  ## Returns
    * List of matching Notion pages
  """
  def find_page_by_name(name) do
    response =
      NotionClient.search(name, %{"filter" => %{"property" => "object", "value" => "page"}})

    response["results"]
  end

  @doc """
  Find faction in Notion by name.

  ## Parameters
    * `name` - The faction name to search for

  ## Returns
    * List of matching faction pages (empty list if not found)
  """
  def find_faction_by_name(name) do
    filter = %{
      "and" => [
        %{
          "property" => "Name",
          "rich_text" => %{"equals" => name}
        }
      ]
    }

    response = NotionClient.database_query(factions_database_id(), %{"filter" => filter})
    response["results"]
  end

  @doc """
  Find image block in Notion page.

  ## Parameters
    * `page` - Notion page with "id" field

  ## Returns
    * Image block if found, nil otherwise
  """
  def find_image_block(page) do
    response = NotionClient.get_block_children(page["id"])
    results = response["results"]

    if results do
      Enum.find(results, fn block -> block["type"] == "image" end)
    end
  end

  @doc """
  Add image to Notion page from character.
  """
  def add_image_to_notion(%Character{image_url: nil}), do: nil

  def add_image_to_notion(%Character{} = character) do
    child = %{
      "object" => "block",
      "type" => "image",
      "image" => %{
        "type" => "external",
        "external" => %{"url" => character.image_url}
      }
    }

    NotionClient.append_block_children(character.notion_page_id, [child])
  rescue
    error ->
      Logger.warning("Failed to add image to Notion: #{inspect(error)}")
      nil
  end

  @doc """
  Add image from Notion to character.
  Downloads image from Notion and uploads to ImageKit, then attaches to character.

  Returns `{:ok, result}` on success (including when skipped), `{:error, reason}` on failure.

  Note: Notion file URLs (type "file") expire after approximately 1 hour.
  This function should be called immediately after extracting the URL from Notion,
  not in a delayed or asynchronous context.
  """
  def add_image(page, %Character{} = character) do
    # Check if character already has an image via ActiveStorage
    existing_image_url = ShotElixir.ActiveStorage.get_image_url("Character", character.id)

    if existing_image_url do
      {:ok, :skipped_existing_image}
    else
      case find_image_block(page) do
        nil ->
          {:ok, :no_image_block}

        image_block ->
          {image_url, is_notion_file} = extract_image_url_with_type(image_block)

          if image_url do
            # Warn about Notion file URL expiration
            if is_notion_file do
              Logger.warning(
                "Notion file URL detected for character #{character.id}. " <>
                  "Download must be immediate as these URLs expire after ~1 hour."
              )
            end

            download_and_attach_image(image_url, character)
          else
            {:ok, :no_image_url}
          end
      end
    end
  end

  # Returns {url, is_notion_file} tuple
  defp extract_image_url_with_type(%{"type" => "image", "image" => image_data}) do
    case image_data do
      %{"type" => "external", "external" => %{"url" => url}} -> {url, false}
      %{"type" => "file", "file" => %{"url" => url}} -> {url, true}
      _ -> {nil, false}
    end
  end

  defp extract_image_url_with_type(_), do: {nil, false}

  defp download_and_attach_image(url, %Character{} = character) do
    # Create a unique temp file path using erlang unique integer (more robust than rand)
    unique_id = :erlang.unique_integer([:positive])
    temp_path = Path.join(System.tmp_dir!(), "notion_image_#{character.id}_#{unique_id}")

    try do
      # First, try to create the temp file to catch permission/disk errors early
      case File.open(temp_path, [:write, :binary]) do
        {:ok, file} ->
          File.close(file)
          # File created successfully, now download into it
          do_download_and_attach(url, temp_path, character)

        {:error, reason} ->
          Logger.error("Failed to create temp file #{temp_path}: #{inspect(reason)}")
          {:error, {:temp_file_creation_failed, reason}}
      end
    after
      # Clean up temp files properly
      cleanup_temp_files(temp_path)
    end
  rescue
    error ->
      Logger.error("Exception downloading Notion image: #{inspect(error)}")
      {:error, error}
  end

  defp do_download_and_attach(url, temp_path, character) do
    # Download the image to memory first (safer than streaming to disk for partial file handling)
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 0 ->
        # Write to temp file
        case File.write(temp_path, body) do
          :ok ->
            # Determine file extension from URL or default to jpg
            extension = url |> URI.parse() |> Map.get(:path, "") |> Path.extname()
            extension = if extension == "", do: ".jpg", else: extension

            # Rename temp file with proper extension
            final_path = temp_path <> extension

            case File.rename(temp_path, final_path) do
              :ok ->
                # Store final_path for cleanup (using process dictionary as simple tracker)
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
    # Upload to ImageKit
    case ShotElixir.Services.ImagekitService.upload_file(final_path, %{
           folder: "/chi-war-#{Mix.env()}/characters",
           file_name: "#{character.id}#{extension}"
         }) do
      {:ok, upload_result} ->
        # Attach to character via ActiveStorage
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
    # Clean up the original temp path
    File.rm(temp_path)

    # Clean up the final path if it was set
    case Process.get(:notion_final_path) do
      nil -> :ok
      final_path -> File.rm(final_path)
    end

    # Clear process dictionary
    Process.delete(:notion_final_path)
  end

  @doc """
  Extract description fields from Notion page.
  """
  def get_description(page) do
    props = page["properties"]

    %{
      "Age" => get_rich_text_content(props, "Age"),
      "Height" => get_rich_text_content(props, "Height"),
      "Weight" => get_rich_text_content(props, "Weight"),
      "Eye Color" => get_rich_text_content(props, "Eye Color"),
      "Hair Color" => get_rich_text_content(props, "Hair Color"),
      "Appearance" => get_rich_text_content(props, "Description"),
      "Style of Dress" => get_rich_text_content(props, "Style of Dress"),
      "Melodramatic Hook" => get_rich_text_content(props, "Melodramatic Hook")
    }
  end

  # Private helper functions

  defp notion_faction_properties(name) do
    case find_faction_by_name(name) do
      [faction | _] ->
        %{"relation" => [%{"id" => faction["id"]}]}

      _ ->
        nil
    end
  end

  defp get_rich_text_content(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("rich_text", [])
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end
end
