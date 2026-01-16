defmodule ShotElixir.Helpers.MentionConverter do
  @moduledoc """
  Bidirectional conversion between Chi War @mentions and Notion rich text.

  Chi War stores mentions as HTML spans:
  `<span data-type="mention" data-id="uuid" data-label="Name" data-href="/characters/uuid">@Name</span>`

  Notion uses rich_text arrays with page mentions or URL links.

  This module handles:
  - Chi War → Notion: HTML with mention spans → Notion rich_text array with page mentions
  - Notion → Chi War: Notion rich_text array → HTML with mention spans
  """

  require Logger

  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Adventures.Adventure
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Campaigns.Campaign

  import Ecto.Query

  # Regex to match Chi War mention spans
  # Captures: id, label, href, display text
  @mention_regex ~r/<span[^>]*data-type="mention"[^>]*data-id="([^"]*)"[^>]*data-label="([^"]*)"[^>]*data-href="([^"]*)"[^>]*>@([^<]*)<\/span>/

  # Alternative regex for spans where attributes may be in different order
  @mention_regex_alt ~r/<span[^>]*data-id="([^"]*)"[^>]*data-type="mention"[^>]*data-label="([^"]*)"[^>]*data-href="([^"]*)"[^>]*>@([^<]*)<\/span>/

  # Regex for HTML br tags (used in multiple functions)
  @br_tag_regex ~r/<br\s*\/?>/

  @type entity_type ::
          :character | :site | :party | :faction | :juncture | :adventure | :vehicle

  @type mention_info :: %{
          id: String.t(),
          label: String.t(),
          href: String.t(),
          entity_type: entity_type() | nil,
          notion_page_id: String.t() | nil
        }

  # =============================================================================
  # Chi War → Notion
  # =============================================================================

  @doc """
  Converts HTML with Chi War mention spans to Notion rich_text array.

  For each mention:
  - If the entity has a `notion_page_id`, creates a Notion page mention
  - Otherwise, creates a URL link to chiwar.net

  Returns a list of rich_text objects suitable for Notion API.

  ## Examples

      iex> html = ~s(<p>Hello <span data-type="mention" data-id="abc" data-label="Bob" data-href="/characters/abc">@Bob</span>!</p>)
      iex> MentionConverter.html_to_notion_rich_text(html, campaign)
      [
        %{"type" => "text", "text" => %{"content" => "Hello "}},
        %{"type" => "mention", "mention" => %{"type" => "page", "page" => %{"id" => "notion-page-id"}}},
        %{"type" => "text", "text" => %{"content" => "!"}}
      ]
  """
  @spec html_to_notion_rich_text(String.t() | nil, Campaign.t()) :: [map()]
  def html_to_notion_rich_text(nil, _campaign), do: []
  def html_to_notion_rich_text("", _campaign), do: []

  def html_to_notion_rich_text(html, %Campaign{} = campaign) when is_binary(html) do
    # First, strip HTML tags but preserve mentions
    # Convert <p> and <br> to newlines
    text_with_mentions =
      html
      |> String.replace(~r/<p>/, "")
      |> String.replace(~r/<\/p>/, "\n")
      |> String.replace(@br_tag_regex, "\n")

    # Find all mentions and their positions
    mentions = extract_mentions(text_with_mentions, campaign)

    if Enum.empty?(mentions) do
      # No mentions, just return plain text
      plain_text = strip_all_html(html)

      if plain_text == "",
        do: [],
        else: [%{"type" => "text", "text" => %{"content" => plain_text}}]
    else
      build_notion_rich_text(text_with_mentions, mentions, campaign)
    end
  end

  def html_to_notion_rich_text(_html, _campaign), do: []

  @doc """
  Extracts mention information from HTML text.
  Returns a list of mention info maps with position data.
  """
  @spec extract_mentions(String.t(), Campaign.t()) :: [map()]
  def extract_mentions(html, %Campaign{} = campaign) do
    # Try primary regex first for positions
    mentions_primary = Regex.scan(@mention_regex, html, return: :index)

    {mentions, content_matches} =
      if Enum.empty?(mentions_primary) do
        # Fallback: try alternative regex (different attribute order)
        mentions_alt = Regex.scan(@mention_regex_alt, html, return: :index)
        content_alt = Regex.scan(@mention_regex_alt, html)
        {mentions_alt, content_alt}
      else
        content_primary = Regex.scan(@mention_regex, html)
        {mentions_primary, content_primary}
      end

    # Build mention info with positions
    Enum.zip(mentions, content_matches)
    |> Enum.map(fn {[{start_pos, length} | _captures], [_full_match, id, label, href, _display]} ->
      entity_info = lookup_entity_for_mention(id, href, campaign)

      %{
        start_pos: start_pos,
        length: length,
        id: id,
        label: label,
        href: href,
        entity_type: entity_info[:entity_type],
        notion_page_id: entity_info[:notion_page_id]
      }
    end)
    |> Enum.uniq_by(& &1.start_pos)
    |> Enum.sort_by(& &1.start_pos)
  end

  # Build the Notion rich_text array from text and mentions
  # Uses cons [item | acc] pattern and reverses at the end for O(n) complexity
  defp build_notion_rich_text(text, mentions, _campaign) do
    {rich_text_reversed, last_pos} =
      Enum.reduce(mentions, {[], 0}, fn mention, {acc, current_pos} ->
        # Add text before this mention
        text_before = String.slice(text, current_pos, mention.start_pos - current_pos)

        acc =
          if text_before != "" do
            # Use strip_html_preserve_whitespace for intermediate segments
            plain_before = strip_html_preserve_whitespace(text_before)

            if plain_before != "" do
              [%{"type" => "text", "text" => %{"content" => plain_before}} | acc]
            else
              acc
            end
          else
            acc
          end

        # Add the mention (prepend to accumulator)
        mention_rich_text = mention_to_notion_rich_text(mention)
        acc = [mention_rich_text | acc]

        {acc, mention.start_pos + mention.length}
      end)

    # Add any remaining text after the last mention
    remaining = String.slice(text, last_pos, String.length(text) - last_pos)

    rich_text_reversed =
      if remaining != "" do
        # For trailing text, strip HTML and trim trailing newlines (from </p> conversion)
        plain_remaining =
          remaining
          |> strip_html_preserve_whitespace()
          |> String.trim_trailing("\n")

        if plain_remaining != "" do
          [%{"type" => "text", "text" => %{"content" => plain_remaining}} | rich_text_reversed]
        else
          rich_text_reversed
        end
      else
        rich_text_reversed
      end

    # Reverse to restore correct order
    Enum.reverse(rich_text_reversed)
  end

  # Convert a single mention to Notion rich_text format
  defp mention_to_notion_rich_text(%{notion_page_id: notion_page_id, label: _label})
       when is_binary(notion_page_id) and notion_page_id != "" do
    # Entity has a Notion page - use page mention
    %{
      "type" => "mention",
      "mention" => %{
        "type" => "page",
        "page" => %{"id" => notion_page_id}
      }
    }
  end

  defp mention_to_notion_rich_text(%{href: href, label: label}) when is_binary(href) do
    # No Notion page - use chiwar.net URL link
    url = build_chiwar_url(href)

    %{
      "type" => "text",
      "text" => %{
        "content" => "@#{label}",
        "link" => %{"url" => url}
      }
    }
  end

  defp mention_to_notion_rich_text(%{label: label}) do
    # Fallback - just plain text
    %{
      "type" => "text",
      "text" => %{"content" => "@#{label}"}
    }
  end

  # Build chiwar.net URL from relative href
  defp build_chiwar_url(href) when is_binary(href) do
    if String.starts_with?(href, "http") do
      href
    else
      "https://chiwar.net#{href}"
    end
  end

  defp build_chiwar_url(_), do: "https://chiwar.net"

  # =============================================================================
  # Notion → Chi War
  # =============================================================================

  @doc """
  Converts Notion rich_text array to Chi War HTML with mention spans.

  For each page mention or chiwar.net URL link:
  - Looks up the entity by notion_page_id or parses the URL
  - Creates a Chi War mention span

  Returns HTML string suitable for Chi War description fields.

  ## Examples

      iex> rich_text = [
      ...>   %{"type" => "text", "text" => %{"content" => "Hello "}},
      ...>   %{"type" => "mention", "mention" => %{"type" => "page", "page" => %{"id" => "notion-id"}}},
      ...>   %{"type" => "text", "text" => %{"content" => "!"}}
      ...> ]
      iex> MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)
      "<p>Hello <span data-type=\"mention\" data-id=\"uuid\" data-label=\"Bob\" data-href=\"/characters/uuid\">@Bob</span>!</p>"
  """
  @spec notion_rich_text_to_html([map()], Ecto.UUID.t()) :: String.t()
  def notion_rich_text_to_html(nil, _campaign_id), do: ""
  def notion_rich_text_to_html([], _campaign_id), do: ""

  def notion_rich_text_to_html(rich_text, campaign_id) when is_list(rich_text) do
    content =
      rich_text
      |> Enum.map(&rich_text_block_to_html(&1, campaign_id))
      |> Enum.join("")

    # Wrap in paragraph tags if content exists
    if content == "" do
      ""
    else
      # Split by newlines and wrap each line in <p> tags
      content
      |> String.split("\n")
      |> Enum.map(&"<p>#{&1}</p>")
      |> Enum.join("")
    end
  end

  def notion_rich_text_to_html(_rich_text, _campaign_id), do: ""

  # Convert a single rich_text block to HTML
  defp rich_text_block_to_html(%{"type" => "mention", "mention" => mention_data}, campaign_id) do
    case mention_data do
      %{"type" => "page", "page" => %{"id" => notion_page_id}} ->
        notion_page_mention_to_html(notion_page_id, campaign_id)

      _ ->
        # Unknown mention type - extract plain text if available
        ""
    end
  end

  defp rich_text_block_to_html(
         %{"type" => "text", "text" => %{"content" => content, "link" => %{"url" => url}}},
         campaign_id
       ) do
    # Check if this is a chiwar.net link (potential mention)
    if is_chiwar_url?(url) do
      chiwar_url_to_mention_html(url, content, campaign_id)
    else
      # Regular external link - just return the text content
      escape_html(content)
    end
  end

  defp rich_text_block_to_html(
         %{"type" => "text", "text" => %{"content" => content}},
         _campaign_id
       ) do
    escape_html(content)
  end

  defp rich_text_block_to_html(%{"plain_text" => plain_text}, _campaign_id) do
    escape_html(plain_text)
  end

  defp rich_text_block_to_html(_block, _campaign_id), do: ""

  # Convert a Notion page mention to Chi War HTML
  defp notion_page_mention_to_html(notion_page_id, _campaign_id) do
    case find_entity_by_notion_page_id(notion_page_id) do
      {:ok, entity_type, entity} ->
        build_mention_span(entity, entity_type)

      {:error, :not_found} ->
        # Entity not found - return empty or placeholder
        Logger.warning("Could not find entity for Notion page ID: #{notion_page_id}")
        ""
    end
  end

  # Convert a chiwar.net URL to Chi War mention HTML
  defp chiwar_url_to_mention_html(url, display_text, campaign_id) do
    case parse_chiwar_url(url) do
      {:ok, entity_type, entity_id} ->
        case find_entity_by_id(entity_type, entity_id, campaign_id) do
          {:ok, entity} ->
            build_mention_span(entity, entity_type)

          {:error, _} ->
            # Entity not found - return plain text
            escape_html(display_text)
        end

      :error ->
        # Could not parse URL - return plain text
        escape_html(display_text)
    end
  end

  # Check if URL is a chiwar.net URL
  defp is_chiwar_url?(url) when is_binary(url) do
    String.contains?(url, "chiwar.net") or
      String.starts_with?(url, "/characters") or
      String.starts_with?(url, "/sites") or
      String.starts_with?(url, "/parties") or
      String.starts_with?(url, "/factions") or
      String.starts_with?(url, "/junctures") or
      String.starts_with?(url, "/adventures") or
      String.starts_with?(url, "/vehicles")
  end

  defp is_chiwar_url?(_), do: false

  # Parse a chiwar.net URL to extract entity type and ID
  defp parse_chiwar_url(url) when is_binary(url) do
    # Extract path from full URL or use as-is if already a path
    path =
      case URI.parse(url) do
        %{path: path} when is_binary(path) -> path
        _ -> url
      end

    entity_types = [
      {"characters", :character},
      {"sites", :site},
      {"parties", :party},
      {"factions", :faction},
      {"junctures", :juncture},
      {"adventures", :adventure},
      {"vehicles", :vehicle}
    ]

    Enum.find_value(entity_types, :error, fn {url_segment, entity_type} ->
      case Regex.run(~r/\/#{url_segment}\/([a-f0-9-]+)/, path) do
        [_, id] -> {:ok, entity_type, id}
        _ -> nil
      end
    end)
  end

  defp parse_chiwar_url(_), do: :error

  # Build a Chi War mention span HTML
  defp build_mention_span(entity, entity_type) do
    id = entity.id
    name = entity.name || "Unknown"
    href = "/#{entity_type_to_path(entity_type)}/#{id}"

    ~s(<span data-type="mention" data-id="#{id}" data-label="#{escape_attr(name)}" data-href="#{href}">@#{escape_html(name)}</span>)
  end

  # =============================================================================
  # Entity Lookup Helpers
  # =============================================================================

  @doc """
  Looks up entity information for a mention by ID and href.
  Returns map with :entity_type and :notion_page_id.
  """
  @spec lookup_entity_for_mention(String.t(), String.t(), Campaign.t()) :: map()
  def lookup_entity_for_mention(id, href, %Campaign{} = campaign) do
    entity_type = entity_type_from_href(href)

    case entity_type do
      nil ->
        %{entity_type: nil, notion_page_id: nil}

      type ->
        case find_entity_by_id(type, id, campaign.id) do
          {:ok, entity} ->
            %{
              entity_type: type,
              notion_page_id: get_notion_page_id(entity)
            }

          {:error, _} ->
            %{entity_type: type, notion_page_id: nil}
        end
    end
  end

  # Extract entity type from href
  defp entity_type_from_href(href) when is_binary(href) do
    cond do
      String.contains?(href, "/characters") -> :character
      String.contains?(href, "/sites") -> :site
      String.contains?(href, "/parties") -> :party
      String.contains?(href, "/factions") -> :faction
      String.contains?(href, "/junctures") -> :juncture
      String.contains?(href, "/adventures") -> :adventure
      String.contains?(href, "/vehicles") -> :vehicle
      String.contains?(href, "/weapons") -> :weapon
      String.contains?(href, "/schticks") -> :schtick
      true -> nil
    end
  end

  defp entity_type_from_href(_), do: nil

  # Find entity by type and ID
  # Uses process-level caching to avoid N+1 queries when processing multiple mentions.
  #
  # Cache behavior:
  # - Cache is stored in the process dictionary and persists for the lifetime of the process
  # - In Phoenix, this typically means the cache lasts for a single HTTP request
  # - Cache is automatically cleared when the process terminates
  # - This assumes entities don't change during a single request (safe assumption)
  # - For long-running processes, consider implementing explicit cache invalidation
  defp find_entity_by_id(entity_type, id, campaign_id) do
    schema = entity_type_to_schema(entity_type)

    if schema do
      # Use process dictionary to cache entities by type for this request
      cache_key = {__MODULE__, :entities_by_campaign_and_type, campaign_id, entity_type}

      entities =
        case Process.get(cache_key) do
          nil ->
            query =
              from e in schema,
                where: e.campaign_id == ^campaign_id

            loaded_entities = Repo.all(query)
            Process.put(cache_key, loaded_entities)
            loaded_entities

          cached_entities ->
            cached_entities
        end

      case Enum.find(entities, &(&1.id == id)) do
        nil -> {:error, :not_found}
        entity -> {:ok, entity}
      end
    else
      {:error, :unknown_type}
    end
  end

  # Find entity by Notion page ID
  defp find_entity_by_notion_page_id(nil), do: {:error, :not_found}

  defp find_entity_by_notion_page_id(page_id) do
    # Normalize page_id (Notion sometimes sends with/without dashes)
    normalized_page_id = normalize_uuid(page_id)

    cond do
      character = Repo.get_by(Character, notion_page_id: normalized_page_id) ->
        {:ok, :character, character}

      site = Repo.get_by(Site, notion_page_id: normalized_page_id) ->
        {:ok, :site, site}

      party = Repo.get_by(Party, notion_page_id: normalized_page_id) ->
        {:ok, :party, party}

      faction = Repo.get_by(Faction, notion_page_id: normalized_page_id) ->
        {:ok, :faction, faction}

      juncture = Repo.get_by(Juncture, notion_page_id: normalized_page_id) ->
        {:ok, :juncture, juncture}

      adventure = Repo.get_by(Adventure, notion_page_id: normalized_page_id) ->
        {:ok, :adventure, adventure}

      vehicle = Repo.get_by(Vehicle, notion_page_id: normalized_page_id) ->
        {:ok, :vehicle, vehicle}

      true ->
        {:error, :not_found}
    end
  end

  # Normalize UUID format (handle with/without dashes)
  # Returns normalized UUID with dashes, or original string if invalid
  defp normalize_uuid(uuid) when is_binary(uuid) do
    hex =
      uuid
      |> String.downcase()
      |> String.replace("-", "")

    if String.length(hex) == 32 do
      case hex do
        <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
          e::binary-size(12)>> ->
          "#{a}-#{b}-#{c}-#{d}-#{e}"

        _ ->
          # Fallback for malformed hex strings
          uuid
      end
    else
      uuid
    end
  end

  defp normalize_uuid(_), do: nil

  # Get notion_page_id from entity (handles different types)
  defp get_notion_page_id(%{notion_page_id: notion_page_id}) when is_binary(notion_page_id) do
    notion_page_id
  end

  defp get_notion_page_id(_), do: nil

  # Map entity type to schema module
  defp entity_type_to_schema(:character), do: Character
  defp entity_type_to_schema(:site), do: Site
  defp entity_type_to_schema(:party), do: Party
  defp entity_type_to_schema(:faction), do: Faction
  defp entity_type_to_schema(:juncture), do: Juncture
  defp entity_type_to_schema(:adventure), do: Adventure
  defp entity_type_to_schema(:vehicle), do: Vehicle
  # Weapons and Schticks don't have notion_page_id, so no schema mapping
  defp entity_type_to_schema(_), do: nil

  # Map entity type to URL path segment
  defp entity_type_to_path(:character), do: "characters"
  defp entity_type_to_path(:site), do: "sites"
  defp entity_type_to_path(:party), do: "parties"
  defp entity_type_to_path(:faction), do: "factions"
  defp entity_type_to_path(:juncture), do: "junctures"
  defp entity_type_to_path(:adventure), do: "adventures"
  defp entity_type_to_path(:vehicle), do: "vehicles"
  defp entity_type_to_path(:weapon), do: "weapons"
  defp entity_type_to_path(:schtick), do: "schticks"
  defp entity_type_to_path(_), do: "entities"

  # =============================================================================
  # HTML Helpers
  # =============================================================================

  # Strip all HTML tags (with trim for standalone use)
  defp strip_all_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(@br_tag_regex, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  defp strip_all_html(_), do: ""

  # Strip HTML tags but preserve leading/trailing whitespace (for text segments)
  defp strip_html_preserve_whitespace(text) when is_binary(text) do
    text
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(@br_tag_regex, "\n")
    |> String.replace(~r/<[^>]+>/, "")

    # Don't trim - preserve whitespace at boundaries
  end

  defp strip_html_preserve_whitespace(_), do: ""

  # Escape HTML special characters
  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_html(_), do: ""

  # Escape attribute value
  defp escape_attr(text) when is_binary(text) do
    text
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape_attr(_), do: ""
end
