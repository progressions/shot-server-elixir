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
  Only runs in production environment.
  """
  def sync_character(%Character{} = character) do
    # Only sync in production
    if Application.get_env(:shot_elixir, :env) != :prod do
      {:ok, :skipped_non_production}
    else
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

        {:error, _reason} ->
          # Silent failure matching Rails behavior
          {:ok, :failed_silently}
      end
    end
  rescue
    _ -> {:ok, :failed_silently}
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
    error -> {:error, error}
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
    error -> {:error, error}
  end

  @doc """
  Find or create a character from Notion page data.
  """
  def find_or_create_character_from_notion(page, campaign_id) do
    name = get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])

    character =
      case Characters.get_character_by_name_and_campaign(name, campaign_id) do
        nil ->
          {:ok, char} =
            Characters.create_character(%{
              name: name,
              campaign_id: campaign_id
            })

          char

        char ->
          char
      end

    update_character_from_notion(character)
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
    error -> {:error, error}
  end

  @doc """
  Search for Notion pages by name.
  """
  def find_page_by_name(name) do
    response =
      NotionClient.search(name, %{"filter" => %{"property" => "object", "value" => "page"}})

    response["results"]
  end

  @doc """
  Find faction in Notion by name.
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
    _ -> nil
  end

  @doc """
  Add image from Notion to character.
  Note: This is a placeholder - actual image upload would require
  downloading from Notion URL and uploading to ImageKit/S3.
  """
  def add_image(_page, _character) do
    # TODO: Implement image download and upload if needed
    # For now, skip this as it requires integration with Arc/ImageKit
    nil
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
