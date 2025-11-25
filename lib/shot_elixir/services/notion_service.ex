defmodule ShotElixir.Services.NotionService do
  @moduledoc """
  Business logic layer for Notion API integration.
  Handles character synchronization with Notion database.
  """

  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Repo

  @database_id Application.compile_env(:shot_elixir, :notion)[:database_id] ||
                 "f6fa27ac-19cd-4b17-b218-55acc6d077be"
  @factions_database_id Application.compile_env(:shot_elixir, :notion)[:factions_database_id] ||
                          "0ae94bfa1a754c8fbda28ea50afa5fd5"

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
        require Logger
        Logger.error("Failed to sync character to Notion: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      require Logger
      Logger.error("Exception syncing character to Notion: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Create a new Notion page from character data.
  """
  def create_notion_from_character(%Character{} = character) do
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        Map.put(properties, "Faction", notion_faction_properties(character.faction.name))
      else
        properties
      end

    page =
      NotionClient.create_page(%{
        "parent" => %{"database_id" => @database_id},
        "properties" => properties
      })

    # Update character with notion_page_id
    {:ok, updated_character} =
      Characters.update_character(character, %{notion_page_id: page["id"]})

    # Add image if present
    add_image_to_notion(updated_character)

    {:ok, page}
  rescue
    error ->
      require Logger
      Logger.error("Failed to create Notion page: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Update existing Notion page with character data.
  """
  def update_notion_from_character(%Character{notion_page_id: nil}), do: {:error, :no_page_id}

  def update_notion_from_character(%Character{} = character) do
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        Map.put(properties, "Faction", notion_faction_properties(character.faction.name))
      else
        properties
      end

    NotionClient.update_page(character.notion_page_id, properties)

    # Add image if not present in Notion
    page = NotionClient.get_page(character.notion_page_id)
    image = find_image_block(page)

    unless image do
      add_image_to_notion(character)
    end

    {:ok, page}
  rescue
    error ->
      require Logger
      Logger.error("Failed to update Notion page: #{inspect(error)}")
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
      require Logger
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
      require Logger
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

    response = NotionClient.database_query(@factions_database_id, %{"filter" => filter})
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
      require Logger
      Logger.warning("Failed to add image to Notion: #{inspect(error)}")
      nil
  end

  @doc """
  Add image from Notion to character.
  Downloads image from Notion and uploads to ImageKit, then attaches to character.
  """
  def add_image(page, %Character{} = character) do
    # Skip if character already has an image
    if character.image_url do
      nil
    else
      case find_image_block(page) do
        nil ->
          nil

        image_block ->
          image_url = extract_image_url(image_block)

          if image_url do
            download_and_attach_image(image_url, character)
          end
      end
    end
  end

  defp extract_image_url(%{"type" => "image", "image" => image_data}) do
    case image_data do
      %{"type" => "external", "external" => %{"url" => url}} -> url
      %{"type" => "file", "file" => %{"url" => url}} -> url
      _ -> nil
    end
  end

  defp extract_image_url(_), do: nil

  defp download_and_attach_image(url, %Character{} = character) do
    require Logger

    # Create a temp file for the download
    temp_path =
      System.tmp_dir!() |> Path.join("notion_image_#{character.id}_#{:rand.uniform(100_000)}")

    try do
      # Download the image
      case Req.get(url, into: File.stream!(temp_path)) do
        {:ok, %{status: 200}} ->
          # Determine file extension from URL or default to jpg
          extension = url |> URI.parse() |> Map.get(:path, "") |> Path.extname()
          extension = if extension == "", do: ".jpg", else: extension

          # Rename temp file with proper extension
          final_path = temp_path <> extension
          File.rename!(temp_path, final_path)

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

        {:ok, %{status: status}} ->
          Logger.warning("Failed to download Notion image, status: #{status}")
          {:error, "Download failed with status #{status}"}

        {:error, reason} ->
          Logger.error("Failed to download Notion image: #{inspect(reason)}")
          {:error, reason}
      end
    after
      # Clean up temp files
      File.rm(temp_path)
      File.rm(temp_path <> ".jpg")
      File.rm(temp_path <> ".png")
      File.rm(temp_path <> ".gif")
      File.rm(temp_path <> ".webp")
    end
  rescue
    error ->
      require Logger
      Logger.error("Exception downloading Notion image: #{inspect(error)}")
      {:error, error}
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
