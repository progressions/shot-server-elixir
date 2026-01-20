defmodule ShotElixir.Services.Notion.Mappers do
  @moduledoc """
  Helpers for mapping Notion page structures to Chi War domain attributes and vice versa.
  """

  require Logger

  import Ecto.Query

  alias ShotElixir.Characters.Character
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Helpers.MentionConverter
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Repo
  alias ShotElixir.Services.Notion.Blocks
  alias ShotElixir.Sites.Site

  # ---------------------------------------------------------------------------
  # Notion Relation Helpers (TO Notion)
  # ---------------------------------------------------------------------------

  @doc """
  Generic helper to add a Notion relation based on a loaded association.
  Used by schema modules to add faction/juncture relations to Notion properties.

  ## Parameters
    - properties: The current Notion properties map
    - entity: The entity struct (Character, Site, Party, etc.)
    - assoc_field: The association field atom (e.g., :faction, :juncture)
    - notion_property_name: The Notion property name (e.g., "Faction", "Juncture")

  ## Returns
    The properties map, potentially with the relation added.
  """
  def maybe_add_relation(properties, entity, assoc_field, notion_property_name) do
    assoc = Map.get(entity, assoc_field)

    if Ecto.assoc_loaded?(assoc) and not is_nil(assoc) and not is_nil(assoc.notion_page_id) do
      Map.put(properties, notion_property_name, %{
        "relation" => [%{"id" => assoc.notion_page_id}]
      })
    else
      properties
    end
  end

  @doc """
  Add faction relation if the entity has a faction with a notion_page_id.
  """
  def maybe_add_faction_relation(properties, entity) do
    maybe_add_relation(properties, entity, :faction, "Faction")
  end

  @doc """
  Add juncture relation if the entity has a juncture with a notion_page_id.
  """
  def maybe_add_juncture_relation(properties, entity) do
    maybe_add_relation(properties, entity, :juncture, "Juncture")
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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

  def get_raw_action_values_from_notion(page) do
    props = page["properties"]

    %{
      "Archetype" => get_rich_text_content(props, "Type"),
      "Type" => get_select_content(props, "Enemy Type"),
      "MainAttack" => get_select_content(props, "MainAttack"),
      "SecondaryAttack" => get_select_content(props, "SecondaryAttack"),
      "FortuneType" => get_select_content(props, "FortuneType"),
      "Fortune" => get_number_content(props, "Fortune"),
      "Max Fortune" => get_number_content(props, "Fortune"),
      "Wounds" => get_number_content(props, "Wounds"),
      "Defense" => get_number_content(props, "Defense"),
      "Toughness" => get_number_content(props, "Toughness"),
      "Speed" => get_number_content(props, "Speed"),
      "Guns" => get_number_content(props, "Guns"),
      "Martial Arts" => get_number_content(props, "Martial Arts"),
      "Sorcery" => get_number_content(props, "Sorcery"),
      "Creature" => get_number_content(props, "Creature"),
      "Scroungetech" => get_number_content(props, "Scroungetech"),
      "Mutant" => get_number_content(props, "Mutant"),
      "Damage" => get_number_content(props, "Damage")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def get_notion_name(page) do
    get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])
  end

  def get_rich_text_as_html(props, key, campaign_id) do
    rich_text =
      props
      |> Map.get(key, %{})
      |> Map.get("rich_text", [])

    MentionConverter.notion_rich_text_to_html(rich_text, campaign_id)
  end

  def entity_attributes_from_notion(page, campaign_id) do
    props = page["properties"] || %{}

    %{
      notion_page_id: page["id"],
      name: get_entity_name(props),
      description: get_rich_text_as_html(props, "Description", campaign_id)
    }
    |> maybe_put_at_a_glance(get_checkbox_content(props, "At a Glance"))
    |> maybe_put_faction_id(page, campaign_id)
    |> maybe_put_juncture_id(page, campaign_id)
  end

  # Add faction_id from Notion relation if present
  defp maybe_put_faction_id(attrs, page, campaign_id) do
    case faction_id_from_notion(page, campaign_id) do
      nil -> attrs
      faction_id -> Map.put(attrs, :faction_id, faction_id)
    end
  end

  # Add juncture_id from Notion relation if present
  defp maybe_put_juncture_id(attrs, page, campaign_id) do
    case juncture_id_from_notion(page, campaign_id) do
      nil -> attrs
      juncture_id -> Map.put(attrs, :juncture_id, juncture_id)
    end
  end

  def adventure_attributes_from_notion(page, campaign_id) do
    props = page["properties"] || %{}

    entity_attributes_from_notion(page, campaign_id)
    |> Map.put(:last_synced_to_notion_at, DateTime.utc_now())
    |> maybe_put_if_not_nil(:season, get_number_content(props, "Season"))
    |> maybe_put_if_not_nil(:started_at, get_date_content(props, "Started"))
    |> maybe_put_if_not_nil(:ended_at, get_date_content(props, "Ended"))
  end

  @doc """
  Fetch rich description from Notion page blocks and add to attributes.
  Uses string keys to maintain consistency with other attribute maps.
  """
  def add_rich_description(attributes, page_id, campaign_id, token) do
    case Blocks.fetch_rich_description(page_id, campaign_id, token) do
      {:ok, %{markdown: markdown, mentions: mentions}} ->
        attributes
        |> Map.put("rich_description", markdown)
        |> Map.put("mentions", mentions)

      {:error, reason} ->
        Logger.warning("Failed to fetch rich description for page #{page_id}: #{inspect(reason)}")
        attributes
    end
  end

  def juncture_as_notion(%Juncture{} = juncture) do
    properties = Juncture.as_notion(juncture)

    location_ids =
      from(s in Site,
        where: s.juncture_id == ^juncture.id and not is_nil(s.notion_page_id),
        select: s.notion_page_id
      )
      |> Repo.all()

    people_ids =
      from(c in Character,
        where: c.juncture_id == ^juncture.id and not is_nil(c.notion_page_id),
        select: c.notion_page_id
      )
      |> Repo.all()

    properties
    |> Map.put("Locations", %{"relation" => Enum.map(location_ids, &%{"id" => &1})})
    |> Map.put("People", %{"relation" => Enum.map(people_ids, &%{"id" => &1})})
  end

  @doc """
  Extract character IDs from a Notion page's relation property.
  Tries property names in order: "People", "Characters", "Natives".
  Returns {:ok, character_ids} if the relation is found, :skip otherwise.
  """
  def character_ids_from_notion(page, campaign_id) do
    relation_ids_from_notion(page, campaign_id, ["People", "Characters", "Natives"], Character)
  end

  @doc """
  Extract site IDs from a Notion page's relation property.
  Tries property names in order: "Locations", "Sites".
  Returns {:ok, site_ids} if the relation is found, :skip otherwise.
  """
  def site_ids_from_notion(page, campaign_id) do
    relation_ids_from_notion(page, campaign_id, ["Locations", "Sites"], Site)
  end

  @doc """
  Extract hero character IDs from a Notion page's hero relation property.
  Tries property names in order: "Character", "Characters", "Heroes".
  Note: "Character"/"Characters" are checked here for adventures that use
  singular naming conventions, distinct from the "People"/"Natives" relations
  used by character_ids_from_notion/2 for junctures/parties.
  Returns {:ok, character_ids} if the relation is found, :skip otherwise.
  """
  def hero_ids_from_notion(page, campaign_id) do
    relation_ids_from_notion(page, campaign_id, ["Character", "Characters", "Heroes"], Character)
  end

  @doc """
  Extract villain character IDs from a Notion page's villain relation property.
  Tries property names in order: "Villains", "Villain", "Antagonists".
  Returns {:ok, character_ids} if the relation is found, :skip otherwise.
  """
  def villain_ids_from_notion(page, campaign_id) do
    relation_ids_from_notion(page, campaign_id, ["Villains", "Villain", "Antagonists"], Character)
  end

  @doc """
  Extract member character IDs from a Notion page's member relation property.
  Tries property names in order: "Members", "Characters".
  Returns {:ok, character_ids} if the relation is found, :skip otherwise.
  """
  def member_ids_from_notion(page, campaign_id) do
    relation_ids_from_notion(page, campaign_id, ["Members", "Characters"], Character)
  end

  @doc """
  Extract faction_id from a Notion page's faction relation property.
  Tries property names in order: "Faction", "Factions".
  Returns the first matching faction's ID, or nil if not found.
  """
  def faction_id_from_notion(page, campaign_id) do
    case relation_id_from_notion(page, campaign_id, ["Faction", "Factions"], Faction) do
      {:ok, id} -> id
      :skip -> nil
    end
  end

  @doc """
  Extract juncture_id from a Notion page's juncture relation property.
  Tries property names in order: "Juncture", "Junctures", "Time Period".
  Returns the first matching juncture's ID, or nil if not found.
  """
  def juncture_id_from_notion(page, campaign_id) do
    case relation_id_from_notion(
           page,
           campaign_id,
           ["Juncture", "Junctures", "Time Period"],
           Juncture
         ) do
      {:ok, id} -> id
      :skip -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Extract a single entity ID from a Notion relation property (for belongs_to associations).
  # Returns {:ok, id} if found, :skip if the relation property doesn't exist.
  defp relation_id_from_notion(page, campaign_id, property_names, schema) do
    relation =
      property_names
      |> Enum.find_value(fn key ->
        case get_in(page, ["properties", key, "relation"]) do
          relations when is_list(relations) and length(relations) > 0 -> relations
          _ -> nil
        end
      end)

    case relation do
      nil ->
        :skip

      [first | _] ->
        page_id = first["id"]

        if is_binary(page_id) do
          id =
            from(entity in schema,
              where: entity.notion_page_id == ^page_id and entity.campaign_id == ^campaign_id,
              select: entity.id
            )
            |> Repo.one()

          {:ok, id}
        else
          {:ok, nil}
        end
    end
  end

  # Shared helper for extracting entity IDs from Notion relation properties.
  # Tries each property name in order until one is found with a relation.
  defp relation_ids_from_notion(page, campaign_id, property_names, schema) do
    relation =
      property_names
      |> Enum.find_value(fn key ->
        case get_in(page, ["properties", key, "relation"]) do
          relations when is_list(relations) -> relations
          _ -> nil
        end
      end)

    case relation do
      nil ->
        :skip

      relations ->
        page_ids =
          relations
          |> Enum.map(& &1["id"])
          |> Enum.filter(&is_binary/1)

        ids =
          case page_ids do
            [] ->
              []

            _ ->
              from(entity in schema,
                where: entity.notion_page_id in ^page_ids and entity.campaign_id == ^campaign_id,
                select: entity.id
              )
              |> Repo.all()
          end

        {:ok, ids}
    end
  end

  defp get_rich_text_content(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("rich_text", [])
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end

  defp get_select_content(props, key) do
    case get_in(props, [key, "select"]) do
      %{"name" => name} -> name
      _ -> nil
    end
  end

  defp get_number_content(props, key) do
    get_in(props, [key, "number"])
  end

  defp get_date_content(props, key) do
    case get_in(props, [key, "date", "start"]) do
      date_str when is_binary(date_str) ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp get_entity_name(props) do
    title = get_title_content(props, "Name")
    if title != "", do: title, else: get_rich_text_content(props, "Name")
  end

  defp get_title_content(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("title", [])
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end

  defp get_checkbox_content(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("checkbox")
  end

  defp maybe_put_at_a_glance(attrs, at_a_glance) do
    if is_boolean(at_a_glance) do
      Map.put(attrs, :at_a_glance, at_a_glance)
    else
      attrs
    end
  end

  defp maybe_put_if_not_nil(map, _key, nil), do: map
  defp maybe_put_if_not_nil(map, key, value), do: Map.put(map, key, value)
end
