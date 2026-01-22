defmodule ShotElixir.Services.Notion.Blocks do
  @moduledoc """
  Utilities for fetching and parsing Notion blocks into plain text or markdown
  with mention resolution.
  """

  require Logger

  alias ShotElixir.Adventures.Adventure
  alias ShotElixir.Characters.Character
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Parties.Party
  alias ShotElixir.Repo
  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Sites.Site

  # ---------------------------------------------------------------------------
  # Session helpers
  # ---------------------------------------------------------------------------

  def extract_page_title(page) do
    props = page["properties"] || %{}

    title_prop =
      props["Name"] ||
        props["Title"] ||
        props["title"] ||
        Enum.find_value(props, fn {_key, value} ->
          if value["type"] == "title", do: value
        end)

    case title_prop do
      %{"title" => [%{"plain_text" => text} | _]} -> text
      %{"title" => []} -> nil
      _ -> nil
    end
  end

  def extract_page_date(page) do
    props = page["properties"] || %{}

    date_prop = props["Date"]

    case date_prop do
      %{"date" => %{"start" => start_date}} when is_binary(start_date) -> start_date
      _ -> nil
    end
  end

  def fetch_session_notes(query, token) do
    unless token do
      {:error, :no_notion_oauth_token}
    else
      search_query = if String.contains?(query, "session"), do: query, else: "session #{query}"

      results =
        NotionClient.search(search_query, %{
          "filter" => %{"property" => "object", "value" => "page"},
          token: token
        })

      case results["results"] do
        [page | _rest] = pages ->
          blocks = NotionClient.get_block_children(page["id"], token: token)
          content = parse_blocks_to_text(blocks["results"] || [])

          {:ok,
           %{
             title: extract_page_title(page),
             page_id: page["id"],
             content: content,
             pages:
               Enum.map(pages, fn p ->
                 %{id: p["id"], title: extract_page_title(p), date: extract_page_date(p)}
               end)
           }}

        [] ->
          {:error, :not_found}

        nil ->
          {:error, :not_found}
      end
    end
  rescue
    error ->
      Logger.error(
        "Failed to fetch session notes for query=#{inspect(query)}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, error}
  end

  def fetch_session_by_id(page_id, token) do
    unless token do
      {:error, :no_notion_oauth_token}
    else
      page = NotionClient.get_page(page_id, token: token)

      case page do
        %{"id" => _id} ->
          blocks = NotionClient.get_block_children(page_id, token: token)
          content = parse_blocks_to_text(blocks["results"] || [])
          {:ok, %{title: extract_page_title(page), page_id: page_id, content: content}}

        %{"code" => error_code, "message" => message} ->
          {:error, {:notion_api_error, error_code, message}}

        _ ->
          {:error, :not_found}
      end
    end
  rescue
    error ->
      Logger.error("Failed to fetch session by ID: #{Exception.message(error)}")
      {:error, error}
  end

  def parse_blocks_to_text(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&parse_block/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def parse_blocks_to_text(_), do: ""

  # ---------------------------------------------------------------------------
  # Adventures/pages
  # ---------------------------------------------------------------------------

  def fetch_adventure(query) do
    response =
      NotionClient.search(query, %{"filter" => %{"property" => "object", "value" => "page"}})

    pages =
      (response["results"] || [])
      |> Enum.map(fn page ->
        title = extract_page_title(page)
        %{id: page["id"], title: title}
      end)
      |> Enum.filter(fn page -> page.title && page.title != "" end)

    case pages do
      [] ->
        {:ok, %{pages: [], title: nil, page_id: nil, content: nil}}

      [first | _rest] ->
        case fetch_page_content(first.id) do
          {:ok, content} ->
            {:ok, %{pages: pages, title: first.title, page_id: first.id, content: content}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  rescue
    error ->
      Logger.error("Failed to search adventures: #{Exception.message(error)}")
      {:error, error}
  end

  def fetch_adventure_by_id(page_id) do
    page = NotionClient.get_page(page_id)

    case page do
      %{"code" => error_code, "message" => message} ->
        {:error, {:notion_api_error, error_code, message}}

      %{"id" => id} ->
        title = extract_page_title(page)

        case fetch_page_content(id) do
          {:ok, content} -> {:ok, %{title: title, page_id: id, content: content}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :unexpected_notion_response}
    end
  rescue
    error ->
      Logger.error("Failed to fetch adventure by ID: #{Exception.message(error)}")
      {:error, error}
  end

  def fetch_page_content(page_id) do
    response = NotionClient.get_block_children(page_id)

    case response do
      %{"results" => blocks} when is_list(blocks) ->
        content = blocks_to_text(blocks)
        {:ok, content}

      %{"code" => error_code, "message" => message} ->
        {:error, {:notion_api_error, error_code, message}}

      _ ->
        {:error, :unexpected_notion_response}
    end
  rescue
    error ->
      Logger.error("Failed to fetch page content: #{Exception.message(error)}")
      {:error, error}
  end

  def fetch_rich_description(page_id, campaign_id, token) do
    response = NotionClient.get_block_children(page_id, token: token)

    case response do
      %{"results" => blocks} when is_list(blocks) ->
        # Split blocks at "GM Only" heading
        {public_blocks, gm_only_blocks} = split_at_gm_only_heading(blocks)

        # Convert each set to markdown
        {markdown, public_mentions} = blocks_to_markdown_with_mentions(public_blocks, campaign_id)

        {gm_only_markdown, gm_only_mentions} =
          blocks_to_markdown_with_mentions(gm_only_blocks, campaign_id)

        # Merge mentions from both sections
        all_mentions = merge_mentions(public_mentions, gm_only_mentions)

        {:ok,
         %{
           markdown: markdown,
           mentions: all_mentions,
           gm_only_markdown: if(gm_only_markdown == "", do: nil, else: gm_only_markdown)
         }}

      %{"code" => error_code, "message" => message} ->
        {:error, {:notion_api_error, error_code, message}}

      _ ->
        {:error, :unexpected_notion_response}
    end
  rescue
    error ->
      Logger.error("Failed to fetch rich description: #{Exception.message(error)}")
      {:error, error}
  end

  @doc """
  Split blocks at a heading_1 with text "GM Only" (case-insensitive).
  Returns {public_blocks, gm_only_blocks} where gm_only_blocks excludes the heading itself.
  """
  def split_at_gm_only_heading(blocks) do
    gm_only_index =
      Enum.find_index(blocks, fn block ->
        block["type"] == "heading_1" &&
          is_gm_only_heading?(block)
      end)

    case gm_only_index do
      nil ->
        # No GM Only section found
        {blocks, []}

      idx ->
        # Split at the heading, exclude the "GM Only" heading itself from gm_only section
        public_blocks = Enum.take(blocks, idx)
        # Skip the heading itself (+1) when taking GM-only blocks
        gm_only_blocks = Enum.drop(blocks, idx + 1)
        {public_blocks, gm_only_blocks}
    end
  end

  defp is_gm_only_heading?(block) do
    heading_text = extract_heading_text(block)
    normalized = heading_text |> String.downcase() |> String.trim()
    normalized == "gm only"
  end

  defp extract_heading_text(%{"heading_1" => %{"rich_text" => rich_text}}) do
    rich_text
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end

  defp extract_heading_text(_), do: ""

  # ---------------------------------------------------------------------------
  # Block parsing helpers
  # ---------------------------------------------------------------------------

  defp parse_block(%{"type" => "heading_1"} = block) do
    text = extract_rich_text_for_session(block["heading_1"]["rich_text"])
    "# #{text}\n"
  end

  defp parse_block(%{"type" => "heading_2"} = block) do
    text = extract_rich_text_for_session(block["heading_2"]["rich_text"])
    "## #{text}\n"
  end

  defp parse_block(%{"type" => "heading_3"} = block) do
    text = extract_rich_text_for_session(block["heading_3"]["rich_text"])
    "### #{text}\n"
  end

  defp parse_block(%{"type" => "paragraph"} = block) do
    text = extract_rich_text_for_session(block["paragraph"]["rich_text"])
    if text == "", do: nil, else: "#{text}\n"
  end

  defp parse_block(%{"type" => "bulleted_list_item"} = block) do
    text = extract_rich_text_for_session(block["bulleted_list_item"]["rich_text"])
    "- #{text}"
  end

  defp parse_block(%{"type" => "numbered_list_item"} = block) do
    text = extract_rich_text_for_session(block["numbered_list_item"]["rich_text"])
    "1. #{text}"
  end

  defp parse_block(%{"type" => "to_do"} = block) do
    text = extract_rich_text_for_session(block["to_do"]["rich_text"])
    checked = if block["to_do"]["checked"], do: "x", else: " "
    "- [#{checked}] #{text}"
  end

  defp parse_block(%{"type" => "toggle"} = block) do
    text = extract_rich_text_for_session(block["toggle"]["rich_text"])
    "▸ #{text}"
  end

  defp parse_block(%{"type" => "quote"} = block) do
    text = extract_rich_text_for_session(block["quote"]["rich_text"])
    "> #{text}"
  end

  defp parse_block(%{"type" => "callout"} = block) do
    text = extract_rich_text_for_session(block["callout"]["rich_text"])
    icon = get_in(block, ["callout", "icon", "emoji"]) || "💡"
    "> #{icon} #{text}"
  end

  defp parse_block(%{"type" => "code"} = block) do
    text = extract_rich_text_for_session(block["code"]["rich_text"])
    lang = block["code"]["language"] || ""
    "```#{lang}\n#{text}\n```"
  end

  defp parse_block(%{"type" => "divider"}), do: "\n---\n"
  defp parse_block(%{"type" => "child_page"} = block), do: "📄 #{block["child_page"]["title"]}"

  defp parse_block(%{"type" => "child_database"} = block),
    do: "📊 #{block["child_database"]["title"]}"

  defp parse_block(%{"type" => "bookmark"} = block) do
    url = block["bookmark"]["url"]
    caption = extract_rich_text_for_session(block["bookmark"]["caption"] || [])
    if caption != "", do: "[#{caption}](#{url})", else: "🔗 #{url}"
  end

  defp parse_block(%{"type" => "link_preview"} = block) do
    url = block["link_preview"]["url"]
    "🔗 #{url}"
  end

  defp parse_block(%{"type" => "table_of_contents"}), do: "[Table of Contents]"
  defp parse_block(%{"type" => "column_list"}), do: nil
  defp parse_block(%{"type" => "column"}), do: nil
  defp parse_block(_block), do: nil

  defp extract_rich_text_for_session(nil), do: ""

  defp extract_rich_text_for_session(rich_text) when is_list(rich_text) do
    rich_text
    |> Enum.map(fn rt ->
      text = rt["plain_text"] || ""

      case rt["type"] do
        "mention" ->
          mention = rt["mention"]

          case mention["type"] do
            "page" -> "@#{text}"
            "user" -> "@#{text}"
            "date" -> "📅 #{text}"
            _ -> text
          end

        _ ->
          text
      end
    end)
    |> Enum.join("")
  end

  defp extract_rich_text_for_session(_), do: ""

  # ---------------------------------------------------------------------------
  # Markdown with mentions
  # ---------------------------------------------------------------------------

  defp blocks_to_markdown_with_mentions(blocks, campaign_id) do
    {text_parts, all_mentions} =
      blocks
      |> Enum.reduce({[], %{}}, fn block, {texts, mentions} ->
        {text, block_mentions} = block_to_markdown(block, campaign_id)

        if text do
          merged_mentions = merge_mentions(mentions, block_mentions)
          {[text | texts], merged_mentions}
        else
          {texts, mentions}
        end
      end)

    markdown = text_parts |> Enum.reverse() |> Enum.join("\n\n")
    {markdown, all_mentions}
  end

  defp block_to_markdown(%{"type" => type} = block, campaign_id) do
    case type do
      "paragraph" ->
        extract_rich_text_with_mentions(get_in(block, ["paragraph", "rich_text"]), campaign_id)

      "heading_1" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["heading_1", "rich_text"]), campaign_id)

        {"# #{text}", mentions}

      "heading_2" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["heading_2", "rich_text"]), campaign_id)

        {"## #{text}", mentions}

      "heading_3" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["heading_3", "rich_text"]), campaign_id)

        {"### #{text}", mentions}

      "bulleted_list_item" ->
        {text, mentions} =
          extract_rich_text_with_mentions(
            get_in(block, ["bulleted_list_item", "rich_text"]),
            campaign_id
          )

        {"- #{text}", mentions}

      "numbered_list_item" ->
        {text, mentions} =
          extract_rich_text_with_mentions(
            get_in(block, ["numbered_list_item", "rich_text"]),
            campaign_id
          )

        {"1. #{text}", mentions}

      "to_do" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["to_do", "rich_text"]), campaign_id)

        checked = if get_in(block, ["to_do", "checked"]), do: "[x]", else: "[ ]"
        {"- #{checked} #{text}", mentions}

      "toggle" ->
        extract_rich_text_with_mentions(get_in(block, ["toggle", "rich_text"]), campaign_id)

      "quote" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["quote", "rich_text"]), campaign_id)

        {"> #{text}", mentions}

      "callout" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["callout", "rich_text"]), campaign_id)

        {"> #{text}", mentions}

      "code" ->
        {text, mentions} =
          extract_rich_text_with_mentions(get_in(block, ["code", "rich_text"]), campaign_id)

        language = get_in(block, ["code", "language"]) || ""
        {"```#{language}\n#{text}\n```", mentions}

      "divider" ->
        {"---", %{}}

      "table_of_contents" ->
        {nil, %{}}

      "image" ->
        {nil, %{}}

      "video" ->
        {"[Video]", %{}}

      "file" ->
        {"[File]", %{}}

      "pdf" ->
        {"[PDF]", %{}}

      "bookmark" ->
        url = get_in(block, ["bookmark", "url"])
        {"[Bookmark](#{url})", %{}}

      "link_preview" ->
        url = get_in(block, ["link_preview", "url"])
        {"[Link](#{url})", %{}}

      "child_page" ->
        title = get_in(block, ["child_page", "title"]) || "Untitled page"
        {"[Page: #{title}]", %{}}

      "child_database" ->
        title = get_in(block, ["child_database", "title"]) || "Untitled database"
        {"[Database: #{title}]", %{}}

      _ ->
        {nil, %{}}
    end
  end

  defp block_to_markdown(_, _campaign_id), do: {nil, %{}}

  defp extract_rich_text_with_mentions(nil, _campaign_id), do: {"", %{}}
  defp extract_rich_text_with_mentions([], _campaign_id), do: {"", %{}}

  defp extract_rich_text_with_mentions(rich_text, campaign_id) when is_list(rich_text) do
    {text_parts, mentions} =
      rich_text
      |> Enum.reduce({[], %{}}, fn item, {texts, acc_mentions} ->
        {text, item_mentions} = rich_text_item_to_markdown(item, campaign_id)
        merged_mentions = merge_mentions(acc_mentions, item_mentions)
        {[text | texts], merged_mentions}
      end)

    text = text_parts |> Enum.reverse() |> Enum.join("")
    {text, mentions}
  end

  defp rich_text_item_to_markdown(
         %{"type" => "mention", "mention" => mention} = item,
         campaign_id
       ) do
    case mention do
      %{"type" => "page", "page" => %{"id" => page_id}} ->
        resolve_page_mention(page_id, item["plain_text"] || "Unknown", campaign_id)

      %{"type" => "user"} ->
        {item["plain_text"] || "@User", %{}}

      %{"type" => "date"} ->
        {item["plain_text"] || "", %{}}

      %{"type" => "database"} ->
        {item["plain_text"] || "[Database]", %{}}

      _ ->
        {item["plain_text"] || "", %{}}
    end
  end

  defp rich_text_item_to_markdown(%{"type" => "text"} = item, _campaign_id) do
    text = get_in(item, ["text", "content"]) || ""
    annotations = item["annotations"] || %{}

    formatted =
      text
      |> maybe_apply_bold(annotations["bold"])
      |> maybe_apply_italic(annotations["italic"])
      |> maybe_apply_strikethrough(annotations["strikethrough"])
      |> maybe_apply_code(annotations["code"])

    formatted =
      case get_in(item, ["text", "link", "url"]) do
        nil -> formatted
        url -> "[#{formatted}](#{url})"
      end

    {formatted, %{}}
  end

  defp rich_text_item_to_markdown(item, _campaign_id) do
    {item["plain_text"] || "", %{}}
  end

  defp resolve_page_mention(page_id, display_name, campaign_id) do
    normalized_id = normalize_uuid(page_id)

    cond do
      character = Repo.get_by(Character, notion_page_id: normalized_id, campaign_id: campaign_id) ->
        mention_text = "[[@character:#{character.id}|#{display_name}]]"
        {mention_text, %{"character" => [character.id]}}

      site = Repo.get_by(Site, notion_page_id: normalized_id, campaign_id: campaign_id) ->
        mention_text = "[[@site:#{site.id}|#{display_name}]]"
        {mention_text, %{"site" => [site.id]}}

      party = Repo.get_by(Party, notion_page_id: normalized_id, campaign_id: campaign_id) ->
        mention_text = "[[@party:#{party.id}|#{display_name}]]"
        {mention_text, %{"party" => [party.id]}}

      faction = Repo.get_by(Faction, notion_page_id: normalized_id, campaign_id: campaign_id) ->
        mention_text = "[[@faction:#{faction.id}|#{display_name}]]"
        {mention_text, %{"faction" => [faction.id]}}

      juncture = Repo.get_by(Juncture, notion_page_id: normalized_id, campaign_id: campaign_id) ->
        mention_text = "[[@juncture:#{juncture.id}|#{display_name}]]"
        {mention_text, %{"juncture" => [juncture.id]}}

      adventure = Repo.get_by(Adventure, notion_page_id: normalized_id, campaign_id: campaign_id) ->
        mention_text = "[[@adventure:#{adventure.id}|#{display_name}]]"
        {mention_text, %{"adventure" => [adventure.id]}}

      true ->
        {"[[#{display_name}]]", %{}}
    end
  end

  defp normalize_uuid(uuid) when is_binary(uuid) do
    cond do
      String.contains?(uuid, "-") ->
        uuid

      String.length(uuid) == 32 ->
        <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
          e::binary-size(12)>> = uuid

        "#{a}-#{b}-#{c}-#{d}-#{e}"

      true ->
        uuid
    end
  end

  defp merge_mentions(map1, map2) do
    Map.merge(map1, map2, fn _k, v1, v2 -> Enum.uniq(v1 ++ v2) end)
  end

  defp maybe_apply_bold(text, true), do: "**#{text}**"
  defp maybe_apply_bold(text, _), do: text
  defp maybe_apply_italic(text, true), do: "_#{text}_"
  defp maybe_apply_italic(text, _), do: text
  defp maybe_apply_strikethrough(text, true), do: "~~#{text}~~"
  defp maybe_apply_strikethrough(text, _), do: text
  defp maybe_apply_code(text, true), do: "`#{text}`"
  defp maybe_apply_code(text, _), do: text

  defp blocks_to_text(blocks) do
    blocks
    |> Enum.map(&block_to_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp block_to_text(%{"type" => type} = block) do
    case type do
      "paragraph" ->
        extract_rich_text(get_in(block, ["paragraph", "rich_text"]))

      "heading_1" ->
        text = extract_rich_text(get_in(block, ["heading_1", "rich_text"]))
        "# #{text}"

      "heading_2" ->
        text = extract_rich_text(get_in(block, ["heading_2", "rich_text"]))
        "## #{text}"

      "heading_3" ->
        text = extract_rich_text(get_in(block, ["heading_3", "rich_text"]))
        "### #{text}"

      "bulleted_list_item" ->
        text = extract_rich_text(get_in(block, ["bulleted_list_item", "rich_text"]))
        "• #{text}"

      "numbered_list_item" ->
        text = extract_rich_text(get_in(block, ["numbered_list_item", "rich_text"]))
        "- #{text}"

      "to_do" ->
        text = extract_rich_text(get_in(block, ["to_do", "rich_text"]))
        checked = if get_in(block, ["to_do", "checked"]), do: "[x]", else: "[ ]"
        "#{checked} #{text}"

      "toggle" ->
        extract_rich_text(get_in(block, ["toggle", "rich_text"]))

      "quote" ->
        text = extract_rich_text(get_in(block, ["quote", "rich_text"]))
        "> #{text}"

      "callout" ->
        extract_rich_text(get_in(block, ["callout", "rich_text"]))

      "code" ->
        text = extract_rich_text(get_in(block, ["code", "rich_text"]))
        "```\n#{text}\n```"

      "divider" ->
        "---"

      "table_of_contents" ->
        nil

      "image" ->
        nil

      "video" ->
        "[Video]"

      "file" ->
        "[File]"

      "pdf" ->
        "[PDF]"

      "bookmark" ->
        url = get_in(block, ["bookmark", "url"])
        "[Bookmark: #{url}]"

      "link_preview" ->
        url = get_in(block, ["link_preview", "url"])
        "[Link: #{url}]"

      "child_page" ->
        title = get_in(block, ["child_page", "title"]) || "Untitled page"
        "[Page: #{title}]"

      "child_database" ->
        title = get_in(block, ["child_database", "title"]) || "Untitled database"
        "[Database: #{title}]"

      _ ->
        nil
    end
  end

  defp block_to_text(_), do: nil

  defp extract_rich_text(nil), do: ""
  defp extract_rich_text([]), do: ""

  defp extract_rich_text(rich_text) when is_list(rich_text) do
    rich_text
    |> Enum.map(fn item -> item["plain_text"] || "" end)
    |> Enum.join("")
  end
end
