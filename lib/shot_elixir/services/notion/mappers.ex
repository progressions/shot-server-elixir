defmodule ShotElixir.Services.Notion.Mappers do
  @moduledoc """
  Helpers for mapping Notion page structures to Chi War domain attributes and vice versa.
  """

  require Logger

  import Ecto.Query

  alias ShotElixir.Characters.Character
  alias ShotElixir.Helpers.MentionConverter
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Repo
  alias ShotElixir.Services.Notion.Blocks
  alias ShotElixir.Sites.Site

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
  end

  def adventure_attributes_from_notion(page, campaign_id) do
    props = page["properties"] || %{}

    entity_attributes_from_notion(page, campaign_id)
    |> Map.put(:last_synced_to_notion_at, DateTime.utc_now())
    |> maybe_put_if_not_nil(:season, get_number_content(props, "Season"))
    |> maybe_put_if_not_nil(:started_at, get_date_content(props, "Started"))
    |> maybe_put_if_not_nil(:ended_at, get_date_content(props, "Ended"))
  end

  def add_rich_description(attributes, page_id, campaign_id, token) do
    case Blocks.fetch_rich_description(page_id, campaign_id, token) do
      {:ok, %{markdown: markdown, mentions: mentions}} ->
        attributes
        |> Map.put(:rich_description, markdown)
        |> Map.put(:mentions, mentions)

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

  def character_ids_from_notion(page, campaign_id) do
    relation =
      ["People", "Characters", "Natives"]
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

        character_ids =
          case page_ids do
            [] ->
              []

            _ ->
              from(c in Character,
                where: c.notion_page_id in ^page_ids and c.campaign_id == ^campaign_id,
                select: c.id
              )
              |> Repo.all()
          end

        {:ok, character_ids}
    end
  end

  def site_ids_from_notion(page, campaign_id) do
    relation =
      ["Locations", "Sites"]
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

        site_ids =
          case page_ids do
            [] ->
              []

            _ ->
              from(s in Site,
                where: s.notion_page_id in ^page_ids and s.campaign_id == ^campaign_id,
                select: s.id
              )
              |> Repo.all()
          end

        {:ok, site_ids}
    end
  end

  @doc """
  Extract hero character IDs from a Notion page's character relation property.
  Tries multiple property names: "Character", "Characters", "Heroes".
  Returns {:ok, character_ids} if the relation is found, :skip otherwise.
  """
  def hero_ids_from_notion(page, campaign_id) do
    relation =
      ["Character", "Characters", "Heroes"]
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

        character_ids =
          case page_ids do
            [] ->
              []

            _ ->
              from(c in Character,
                where: c.notion_page_id in ^page_ids and c.campaign_id == ^campaign_id,
                select: c.id
              )
              |> Repo.all()
          end

        {:ok, character_ids}
    end
  end

  @doc """
  Extract villain character IDs from a Notion page's villain relation property.
  Tries multiple property names: "Villains", "Villain", "Antagonists".
  Returns {:ok, character_ids} if the relation is found, :skip otherwise.
  """
  def villain_ids_from_notion(page, campaign_id) do
    relation =
      ["Villains", "Villain", "Antagonists"]
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

        character_ids =
          case page_ids do
            [] ->
              []

            _ ->
              from(c in Character,
                where: c.notion_page_id in ^page_ids and c.campaign_id == ^campaign_id,
                select: c.id
              )
              |> Repo.all()
          end

        {:ok, character_ids}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

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
