# Notion Integration Implementation Specification

## Overview
This document specifies the complete Notion integration for shot-elixir, replicating the exact behavior from shot-server (Rails).

## Database Schema
✅ Already exists in the database:
- `notion_page_id` (UUID) - Stores the Notion page ID
- `last_synced_to_notion_at` (UTC datetime) - Last sync timestamp

✅ Already in Character schema at lines 66-67

## Configuration Required

### config/config.exs
Add to the bottom:
```elixir
# Notion API configuration
config :shot_elixir, :notion,
  token: System.get_env("NOTION_TOKEN"),
  database_id: "f6fa27ac-19cd-4b17-b218-55acc6d077be",
  factions_database_id: "0ae94bfa1a754c8fbda28ea50afa5fd5"
```

### config/prod.exs
Ensure NOTION_TOKEN is available from Fly.io secrets.

## Implementation Files

### 1. Notion Client (lib/shot_elixir/services/notion_client.ex)

HTTP client wrapper using Req for Notion API v1:

```elixir
defmodule ShotElixir.Services.NotionClient do
  @moduledoc """
  HTTP client for Notion API v1.
  Uses Req library for HTTP requests.
  """

  @notion_version "2022-06-28"
  @base_url "https://api.notion.com/v1"

  def client do
    token = Application.get_env(:shot_elixir, :notion)[:token]
    
    Req.new(
      base_url: @base_url,
      headers: [
        {"Authorization", "Bearer #{token}"},
        {"Notion-Version", @notion_version},
        {"Content-Type", "application/json"}
      ]
    )
  end

  def search(query, opts \\ %{}) do
    body = Map.merge(%{"query" => query}, opts)
    
    client()
    |> Req.post!(url: "/search", json: body)
    |> Map.get(:body)
  end

  def database_query(database_id, opts \\ %{}) do
    client()
    |> Req.post!(url: "/databases/#{database_id}/query", json: opts)
    |> Map.get(:body)
  end

  def create_page(params) do
    client()
    |> Req.post!(url: "/pages", json: params)
    |> Map.get(:body)
  end

  def update_page(page_id, properties) do
    client()
    |> Req.patch!(url: "/pages/#{page_id}", json: %{"properties" => properties})
    |> Map.get(:body)
  end

  def get_page(page_id) do
    client()
    |> Req.get!(url: "/pages/#{page_id}")
    |> Map.get(:body)
  end

  def get_block_children(block_id) do
    client()
    |> Req.get!(url: "/blocks/#{block_id}/children")
    |> Map.get(:body)
  end

  def append_block_children(block_id, children) do
    client()
    |> Req.patch!(url: "/blocks/#{block_id}/children", json: %{"children" => children})
    |> Map.get(:body)
  end
end
```

### 2. Character Notion Functions (Add to lib/shot_elixir/characters/character.ex)

Add these functions at the end of the Character module:

```elixir
  # Notion Integration Functions
  
  def as_notion(%__MODULE__{} = character) do
    av = character.action_values || @default_action_values
    desc = character.description || %{}
    
    base_properties = %{
      "Name" => %{"title" => [%{"text" => %{"content" => character.name}}]},
      "Enemy Type" => %{"select" => %{"name" => av["Type"] || "PC"}},
      "Wounds" => %{"number" => av["Wounds"]},
      "Defense" => %{"number" => av["Defense"]},
      "Toughness" => %{"number" => av["Toughness"]},
      "Speed" => %{"number" => av["Speed"]},
      "Fortune" => %{"number" => av["Max Fortune"]},
      "Guns" => %{"number" => av["Guns"]},
      "Martial Arts" => %{"number" => av["Martial Arts"]},
      "Sorcery" => %{"number" => av["Sorcery"]},
      "Mutant" => %{"number" => av["Mutant"]},
      "Scroungetech" => %{"number" => av["Scroungetech"]},
      "Creature" => %{"number" => av["Creature"]},
      "Damage" => %{"rich_text" => [%{"text" => %{"content" => to_string(av["Damage"] || "")}}]},
      "Inactive" => %{"checkbox" => !character.active},
      "Tags" => %{"multi_select" => tags_for_notion(character)},
      "Age" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Age"] || "")}}]},
      "Nicknames" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Nicknames"] || "")}}]},
      "Height" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Height"] || "")}}]},
      "Weight" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Weight"] || "")}}]},
      "Hair Color" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Hair Color"] || "")}}]},
      "Eye Color" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Eye Color"] || "")}}]},
      "Style of Dress" => %{"rich_text" => [%{"text" => %{"content" => to_string(desc["Style of Dress"] || "")}}]},
      "Melodramatic Hook" => %{"rich_text" => [%{"text" => %{"content" => strip_html(desc["Melodramatic Hook"] || "")}}]},
      "Description" => %{"rich_text" => [%{"text" => %{"content" => strip_html(desc["Appearance"] || "")}}]}
    }
    
    # Add optional select fields
    properties = base_properties
    |> maybe_add_select("MainAttack", av["MainAttack"])
    |> maybe_add_select("SecondaryAttack", av["SecondaryAttack"])
    |> maybe_add_select("FortuneType", av["FortuneType"])
    |> maybe_add_archetype(av["Archetype"])
    |> maybe_add_chi_war_link(character)
    
    properties
  end
  
  defp tags_for_notion(character) do
    av = character.action_values || @default_action_values
    tags = []
    
    tags = if av["Type"] != "PC", do: [%{"name" => "NPC"} | tags], else: tags
    tags = if av["Type"], do: [%{"name" => av["Type"]} | tags], else: tags
    
    Enum.filter(tags, & &1)
  end
  
  defp maybe_add_select(properties, _key, nil), do: properties
  defp maybe_add_select(properties, _key, ""), do: properties
  defp maybe_add_select(properties, key, value) do
    Map.put(properties, key, %{"select" => %{"name" => value}})
  end
  
  defp maybe_add_archetype(properties, nil), do: properties
  defp maybe_add_archetype(properties, ""), do: properties
  defp maybe_add_archetype(properties, archetype) do
    Map.put(properties, "Type", %{"rich_text" => [%{"text" => %{"content" => archetype}}]})
  end
  
  defp maybe_add_chi_war_link(properties, character) do
    if Application.get_env(:shot_elixir, :env) == :prod do
      url = "https://chiwar.net/characters/#{character.id}"
      Map.put(properties, "Chi War Link", %{"url" => url})
    else
      properties
    end
  end
  
  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end
  defp strip_html(_), do: ""
  
  def attributes_from_notion(character, page) do
    props = page["properties"]
    
    av = %{
      "Archetype" => get_rich_text(props, "Type"),
      "Type" => get_select(props, "Enemy Type"),
      "MainAttack" => get_select(props, "MainAttack"),
      "SecondaryAttack" => get_select(props, "SecondaryAttack"),
      "FortuneType" => get_select(props, "FortuneType"),
      "Wounds" => av_or_new(character, "Wounds", get_number(props, "Wounds")),
      "Defense" => av_or_new(character, "Defense", get_number(props, "Defense")),
      "Toughness" => av_or_new(character, "Toughness", get_number(props, "Toughness")),
      "Speed" => av_or_new(character, "Speed", get_number(props, "Speed")),
      "Guns" => av_or_new(character, "Guns", get_number(props, "Guns")),
      "Martial Arts" => av_or_new(character, "Martial Arts", get_number(props, "Martial Arts")),
      "Sorcery" => av_or_new(character, "Sorcery", get_number(props, "Sorcery")),
      "Creature" => av_or_new(character, "Creature", get_number(props, "Creature")),
      "Scroungetech" => av_or_new(character, "Scroungetech", get_number(props, "Scroungetech")),
      "Mutant" => av_or_new(character, "Mutant", get_number(props, "Mutant"))
    }
    
    description = %{
      "Age" => get_rich_text(props, "Age"),
      "Height" => get_rich_text(props, "Height"),
      "Weight" => get_rich_text(props, "Weight"),
      "Eye Color" => get_rich_text(props, "Eye Color"),
      "Hair Color" => get_rich_text(props, "Hair Color"),
      "Appearance" => get_rich_text(props, "Description"),
      "Style of Dress" => get_rich_text(props, "Style of Dress"),
      "Melodramatic Hook" => get_rich_text(props, "Melodramatic Hook")
    }
    
    %{
      notion_page_id: page["id"],
      name: get_title(props, "Name"),
      action_values: Map.merge(character.action_values || @default_action_values, av),
      description: Map.merge(character.description || %{}, description)
    }
  end
  
  defp av_or_new(character, key, new_value) when is_nil(new_value), do: nil
  defp av_or_new(character, key, new_value) do
    current = (character.action_values || @default_action_values)[key]
    
    cond do
      is_integer(current) and current > 7 -> current
      true -> new_value
    end
  end
  
  defp get_title(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("title", [])
    |> List.first()
    |> case do
      nil -> nil
      item -> get_in(item, ["plain_text"])
    end
  end
  
  defp get_select(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("select", %{})
    |> Map.get("name")
  end
  
  defp get_number(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("number")
  end
  
  defp get_rich_text(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("rich_text", [])
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end
```

### 3. Notion Service (lib/shot_elixir/services/notion_service.ex)

Continue in next section...

