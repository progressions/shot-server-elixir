defmodule ShotElixir.Services.NotionService do
  @moduledoc """
  Business logic layer for Notion API integration.
  Handles synchronization of characters, sites, parties, factions, and junctures with Notion databases.
  """

  require Logger

  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Factions
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Notion
  alias ShotElixir.Parties
  alias ShotElixir.Parties.Party
  alias ShotElixir.Repo
  alias ShotElixir.Sites
  alias ShotElixir.Sites.Site

  import Ecto.Query

  # =============================================================================
  # Configuration Helpers
  # =============================================================================

  defp get_notion_config(campaign_id, key) do
    campaign = if campaign_id, do: ShotElixir.Campaigns.get_campaign(campaign_id), else: nil

    value =
      if campaign do
        case key do
          :token ->
            case campaign.notion_access_token do
              nil ->
                nil

              encrypted ->
                case ShotElixir.Encrypted.Binary.load(encrypted) do
                  {:ok, token} -> token
                  _ -> nil
                end
            end

          _ ->
            db_key =
              case key do
                :database_id -> "characters"
                :factions_database_id -> "factions"
                :parties_database_id -> "parties"
                :sites_database_id -> "sites"
                :junctures_database_id -> "junctures"
                _ -> to_string(key)
              end

            get_in(campaign.notion_database_ids || %{}, [db_key])
        end
      end

    value || Application.get_env(:shot_elixir, :notion)[key]
  end

  def get_token(campaign_id) do
    get_notion_config(campaign_id, :token)
  end

  defp database_id(campaign_id),
    do: get_notion_config(campaign_id, :database_id) || "f6fa27ac-19cd-4b17-b218-55acc6d077be"

  defp factions_database_id(campaign_id),
    do:
      get_notion_config(campaign_id, :factions_database_id) || "0ae94bfa1a754c8fbda28ea50afa5fd5"

  defp parties_database_id(campaign_id),
    do: get_notion_config(campaign_id, :parties_database_id) || "2e5e0b55d4178083bd93e8a60280209b"

  defp sites_database_id(campaign_id),
    do: get_notion_config(campaign_id, :sites_database_id) || "8ac4e657c540499c977f79b0643b7070"

  defp junctures_database_id(campaign_id),
    do:
      get_notion_config(campaign_id, :junctures_database_id) || "4228eb7fefef470bb9f19a7f5d73c0fc"

  # =============================================================================
  # Character Sync Functions
  # =============================================================================

  def sync_character(%Character{} = character) do
    character = Repo.preload(character, :faction)
    token = get_token(character.campaign_id)

    result =
      if character.notion_page_id do
        update_notion_from_character(character, token)
      else
        create_notion_from_character(character, token)
      end

    case result do
      {:ok, :unlinked} ->
        {:ok, :unlinked}

      {:ok, _} ->
        Characters.update_character(character, %{last_synced_to_notion_at: DateTime.utc_now()})

      {:error, reason} ->
        Logger.error("Failed to sync character to Notion: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Exception syncing character to Notion: #{Exception.message(error)}")
      {:error, error}
  end

  def merge_with_notion(%Character{} = character, notion_page_id) do
    character = Repo.preload(character, :faction)
    token = get_token(character.campaign_id)

    case NotionClient.get_page(notion_page_id, token: token) do
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion API error: #{error_code} - #{message}")
        {:error, {:notion_api_error, error_code, message}}

      nil ->
        {:error, :notion_page_not_found}

      page when is_map(page) ->
        raw_notion_action_values = get_raw_action_values_from_notion(page)
        notion_description = get_description(page)
        notion_name = get_notion_name(page)
        notion_at_a_glance = get_in(page, ["properties", "At a Glance", "checkbox"])

        merged_action_values =
          smart_merge_action_values(
            character.action_values || Character.default_action_values(),
            raw_notion_action_values
          )

        merged_description =
          smart_merge_description(character.description || %{}, notion_description)

        merged_name =
          if blank?(character.name), do: notion_name || character.name, else: character.name

        update_attrs =
          %{
            notion_page_id: notion_page_id,
            name: merged_name,
            action_values: merged_action_values,
            description: merged_description
          }
          |> Character.maybe_put_at_a_glance(notion_at_a_glance)

        case Characters.update_character(character, update_attrs) do
          {:ok, updated_character} ->
            updated_character = Repo.preload(updated_character, :faction)
            update_notion_from_character(updated_character, token)

            updated_character =
              case set_faction_from_notion(
                     updated_character,
                     page,
                     updated_character.campaign_id,
                     token
                   ) do
                {:ok, char} -> char
                _ -> updated_character
              end

            updated_character =
              case set_juncture_from_notion(
                     updated_character,
                     page,
                     updated_character.campaign_id,
                     token
                   ) do
                {:ok, char} -> char
                _ -> updated_character
              end

            add_image(page, updated_character, token)
            Notion.log_success("character", updated_character.id, %{action: "merge"}, page)
            {:ok, updated_character}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  rescue
    error ->
      Logger.error("Exception merging with Notion: #{Exception.message(error)}")
      {:error, error}
  end

  def create_notion_from_character(%Character{} = character, token \\ nil) do
    character = Repo.preload(character, :faction)
    token = token || get_token(character.campaign_id)
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props =
          notion_faction_properties(character.faction.name, character.campaign_id, token)

        if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
      else
        properties
      end

    db_id = database_id(character.campaign_id)
    payload = %{"parent" => %{"database_id" => db_id}, "properties" => properties}
    page = NotionClient.create_page(Map.put(payload, :token, token))

    case page do
      %{"id" => page_id} when is_binary(page_id) ->
        Notion.log_success("character", character.id, payload, page)

        case Characters.update_character(character, %{notion_page_id: page_id}) do
          {:ok, updated_character} ->
            add_image_to_notion(updated_character, token)
            {:ok, page}

          {:error, changeset} ->
            {:error, changeset}
        end

      %{"code" => code, "message" => msg} ->
        Notion.log_error(
          "character",
          character.id,
          payload,
          page,
          "Notion API error: #{code} - #{msg}"
        )

        {:error, {:notion_api_error, code, msg}}

      _ ->
        {:error, :unexpected_notion_response}
    end
  end

  def update_notion_from_character(character, token \\ nil)

  def update_notion_from_character(%Character{notion_page_id: nil}, _token),
    do: {:error, :no_page_id}

  def update_notion_from_character(%Character{} = character, token) do
    token = token || get_token(character.campaign_id)
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props =
          notion_faction_properties(character.faction.name, character.campaign_id, token)

        if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
      else
        properties
      end

    payload = %{"page_id" => character.notion_page_id, "properties" => properties}
    response = NotionClient.update_page(character.notion_page_id, properties, token: token)

    case response do
      %{"code" => "validation_error", "message" => msg} when is_binary(msg) ->
        if String.contains?(String.downcase(msg), "archived"),
          do: handle_archived_page(character, payload, response, msg),
          else: {:error, {:notion_api_error, "validation_error", msg}}

      %{"code" => "object_not_found", "message" => msg} ->
        handle_archived_page(character, payload, response, msg)

      %{"code" => code, "message" => msg} ->
        {:error, {:notion_api_error, code, msg}}

      _ ->
        page = NotionClient.get_page(character.notion_page_id, token: token)
        if !find_image_block(page, token), do: add_image_to_notion(character, token)
        Notion.log_success("character", character.id, payload, response || page)
        {:ok, page}
    end
  end

  def create_character_from_notion(page, campaign_id, token \\ nil) do
    token = token || get_token(campaign_id)
    name = get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])
    unique_name = Characters.generate_unique_name(name, campaign_id)
    {:ok, character} = Characters.create_character(%{name: unique_name, campaign_id: campaign_id})
    character = Repo.preload(character, :faction)
    attributes = Character.attributes_from_notion(character, page)

    {:ok, character} =
      Characters.update_character(character, Map.put(attributes, :notion_page_id, page["id"]))

    description = get_description(page)

    merged_description =
      Map.merge(description, character.description || %{}, fn _k, v1, v2 ->
        if v2 == "" or is_nil(v2), do: v1, else: v2
      end)

    {:ok, character} = Characters.update_character(character, %{description: merged_description})

    {:ok, character} = set_faction_from_notion(character, page, campaign_id, token)
    {:ok, character} = set_juncture_from_notion(character, page, campaign_id, token)
    add_image(page, character, token)
    {:ok, character}
  end

  def update_character_from_notion(character, token \\ nil)

  def update_character_from_notion(%Character{notion_page_id: nil}, _token),
    do: {:error, :no_page_id}

  def update_character_from_notion(%Character{} = character, token) do
    token = token || get_token(character.campaign_id)

    case NotionClient.get_page(character.notion_page_id, token: token) do
      nil ->
        {:error, :notion_page_not_found}

      %{"code" => code, "message" => msg} ->
        {:error, {:notion_api_error, code, msg}}

      page when is_map(page) ->
        attributes = Character.attributes_from_notion(character, page)
        add_image(page, character, token)
        Characters.update_character(character, attributes)
    end
  end

  def handle_archived_page(%Character{} = character, payload, response, message) do
    Notion.log_error(
      "character",
      character.id,
      payload,
      response,
      "Notion page archived/deleted - unlinking: #{message}"
    )

    case Characters.update_character(character, %{notion_page_id: nil}) do
      {:ok, _} -> {:ok, :unlinked}
      {:error, cs} -> {:error, {:unlink_failed, cs}}
    end
  end

  # =============================================================================
  # Search & Discovery
  # =============================================================================

  def list_databases(campaign_id) do
    token = get_token(campaign_id)

    results =
      NotionClient.search("", %{
        "filter" => %{"property" => "object", "value" => "database"},
        :token => token
      })

    case results["results"] do
      databases when is_list(databases) ->
        Enum.map(databases, fn db ->
          %{"id" => db["id"], "title" => extract_page_title(db), "url" => db["url"]}
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def find_page_by_name(name, token \\ nil) do
    results =
      NotionClient.search(name, %{
        "filter" => %{"property" => "object", "value" => "page"},
        :token => token
      })

    case results["results"] do
      pages when is_list(pages) ->
        Enum.map(pages, fn page ->
          %{"id" => page["id"], "title" => extract_page_title(page), "url" => page["url"]}
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def find_pages_in_database(database_id, name, token \\ nil) do
    filter =
      if name == "",
        do: %{},
        else: %{"filter" => %{"property" => "Name", "title" => %{"contains" => name}}}

    response = NotionClient.database_query(database_id, Map.put(filter, :token, token))

    case response["results"] do
      pages when is_list(pages) ->
        Enum.map(pages, fn page ->
          %{"id" => page["id"], "title" => extract_page_title(page), "url" => page["url"]}
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  def find_sites_in_notion(campaign_id, name \\ ""),
    do: find_pages_in_database(sites_database_id(campaign_id), name, get_token(campaign_id))

  def find_parties_in_notion(campaign_id, name \\ ""),
    do: find_pages_in_database(parties_database_id(campaign_id), name, get_token(campaign_id))

  def find_factions_in_notion(campaign_id, name \\ ""),
    do: find_pages_in_database(factions_database_id(campaign_id), name, get_token(campaign_id))

  def find_junctures_in_notion(campaign_id, name \\ ""),
    do: find_pages_in_database(junctures_database_id(campaign_id), name, get_token(campaign_id))

  def find_faction_by_name(name, campaign_id, token) do
    filter = %{
      "and" => [%{"property" => "Name", "rich_text" => %{"equals" => name}}],
      :token => token
    }

    response = NotionClient.database_query(factions_database_id(campaign_id), filter)
    response["results"]
  end

  # =============================================================================
  # Sync Functions
  # =============================================================================

  def sync_site(%Site{} = s),
    do:
      sync_entity(Repo.preload(s, [:faction, :juncture, attunements: :character]), %{
        entity_type: "site",
        database_id: sites_database_id(s.campaign_id),
        update_fn: &Sites.update_site/2,
        as_notion_fn: &Site.as_notion/1,
        token: get_token(s.campaign_id)
      })

  def sync_party(%Party{} = p),
    do:
      sync_entity(Repo.preload(p, [:faction, :juncture, memberships: :character]), %{
        entity_type: "party",
        database_id: parties_database_id(p.campaign_id),
        update_fn: &Parties.update_party/2,
        as_notion_fn: &Party.as_notion/1,
        token: get_token(p.campaign_id)
      })

  def sync_faction(%Faction{} = f),
    do:
      sync_entity(Repo.preload(f, [:characters]), %{
        entity_type: "faction",
        database_id: factions_database_id(f.campaign_id),
        update_fn: &Factions.update_faction/2,
        as_notion_fn: &Faction.as_notion/1,
        token: get_token(f.campaign_id)
      })

  def sync_juncture(%Juncture{} = j),
    do:
      sync_entity(j, %{
        entity_type: "juncture",
        database_id: junctures_database_id(j.campaign_id),
        update_fn: &Junctures.update_juncture/2,
        as_notion_fn: &juncture_as_notion/1,
        token: get_token(j.campaign_id)
      })

  defp sync_entity(entity, %{entity_type: type} = opts) do
    result =
      if entity.notion_page_id,
        do: update_notion_page(entity, opts),
        else: create_notion_page(entity, opts)

    case result do
      {:ok, :unlinked} -> {:ok, :unlinked}
      {:ok, _} -> opts.update_fn.(entity, %{last_synced_to_notion_at: DateTime.utc_now()})
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp create_notion_page(entity, %{entity_type: type} = opts) do
    payload = %{
      "parent" => %{"database_id" => opts.database_id},
      "properties" => opts.as_notion_fn.(entity)
    }

    page = NotionClient.create_page(Map.put(payload, :token, opts.token))

    case page do
      %{"id" => id} ->
        Notion.log_success(type, entity.id, payload, page)

        case opts.update_fn.(entity, %{notion_page_id: id}) do
          {:ok, updated} ->
            add_image_to_notion(updated, opts.token)
            {:ok, page}

          {:error, cs} ->
            {:error, cs}
        end

      _ ->
        {:error, :failed}
    end
  end

  defp update_notion_page(entity, %{entity_type: type} = opts) do
    properties = opts.as_notion_fn.(entity)
    payload = %{"page_id" => entity.notion_page_id, "properties" => properties}
    response = NotionClient.update_page(entity.notion_page_id, properties, token: opts.token)

    case response do
      %{"code" => "object_not_found"} ->
        handle_archived_entity(entity, opts, payload, response, "deleted")

      _ ->
        page = NotionClient.get_page(entity.notion_page_id, token: opts.token)
        if !find_image_block(page, opts.token), do: add_image_to_notion(entity, opts.token)
        Notion.log_success(type, entity.id, payload, response)
        {:ok, response}
    end
  end

  defp handle_archived_entity(entity, opts, payload, response, msg) do
    Notion.log_error(opts.entity_type, entity.id, payload, response, "Archived: #{msg}")

    case opts.update_fn.(entity, %{notion_page_id: nil}) do
      {:ok, _} -> {:ok, :unlinked}
      _ -> {:error, :failed}
    end
  end

  # =============================================================================
  # Shared Helpers
  # =============================================================================

  def find_image_block(page, token \\ nil) do
    case NotionClient.get_block_children(page["id"], token: token) do
      %{"results" => results} -> Enum.find(results, fn b -> b["type"] == "image" end)
      _ -> nil
    end
  end

  def add_image_to_notion(entity, token \\ nil)

  def add_image_to_notion(%{image_url: url, notion_page_id: id}, token)
      when is_binary(url) and url != "" do
    child = %{
      "object" => "block",
      "type" => "image",
      "image" => %{"type" => "external", "external" => %{"url" => url}}
    }

    NotionClient.append_block_children(id, [child], token: token)
  rescue
    _ -> nil
  end

  def add_image_to_notion(_, _), do: nil

  def add_image(page, %Character{} = c, token \\ nil) do
    existing = ShotElixir.ActiveStorage.get_image_url("Character", c.id)

    if existing do
      {:ok, :skipped}
    else
      case find_image_block(page, token) do
        nil ->
          {:ok, :no_image}

        block ->
          {url, is_file} = extract_image_url_with_type(block)
          if url, do: download_and_attach_image(url, c), else: {:ok, :no_url}
      end
    end
  end

  defp extract_image_url_with_type(%{"type" => "image", "image" => d}) do
    case d do
      %{"type" => "external", "external" => %{"url" => u}} -> {u, false}
      %{"type" => "file", "file" => %{"url" => u}} -> {u, true}
      _ -> {nil, false}
    end
  end

  defp extract_image_url_with_type(_), do: {nil, false}

  defp download_and_attach_image(url, c) do
    case validate_image_url(url) do
      :ok -> do_download_with_temp_file(url, c)
      e -> e
    end
  end

  @trusted_image_domains [
    ~r/^prod-files-secure\.s3\.us-west-2\.amazonaws\.com$/,
    ~r/^s3\.us-west-2\.amazonaws\.com$/,
    ~r/^.*\.notion\.so$/,
    ~r/^.*\.notion-static\.com$/,
    ~r/^images\.unsplash\.com$/,
    ~r/^.*\.cloudfront\.net$/
  ]
  defp validate_image_url(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme != "https" -> {:error, :not_https}
      is_nil(uri.host) -> {:error, :no_host}
      !Enum.any?(@trusted_image_domains, &Regex.match?(&1, uri.host)) -> {:error, :untrusted}
      true -> :ok
    end
  end

  defp do_download_with_temp_file(url, c) do
    id = :erlang.unique_integer([:positive])
    path = Path.join(System.tmp_dir!(), "notion_img_#{c.id}_#{id}")

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        File.write!(path, body)
        ext = Path.extname(URI.parse(url).path)
        final = path <> if ext == "", do: ".jpg", else: ext
        File.rename!(path, final)
        upload_and_attach(final, Path.extname(final), c)
        File.rm(final)
        {:ok, :uploaded}

      _ ->
        {:error, :download_failed}
    end
  rescue
    _ -> {:error, :failed}
  end

  defp upload_and_attach(path, ext, c) do
    case ShotElixir.Services.ImagekitService.upload_file(path, %{
           folder: "/chi-war-#{Mix.env()}/characters",
           file_name: "#{c.id}#{ext}"
         }) do
      {:ok, res} -> ShotElixir.ActiveStorage.attach_image("Character", c.id, res)
      e -> e
    end
  end

  defp smart_merge_action_values(local, notion),
    do: Map.merge(local, notion, fn _k, l, n -> if blank?(l, true), do: n, else: l end)

  defp smart_merge_description(local, notion),
    do: Map.merge(local, notion, fn _k, l, n -> if blank?(l), do: n, else: l end)

  defp smart_merge_value(l, n, opts), do: if(blank?(l, opts[:action_value?]), do: n, else: l)

  defp blank?(value), do: blank?(value, false)
  defp blank?(nil, _), do: true
  defp blank?("", _), do: true
  defp blank?(0, true), do: true
  defp blank?("0", true), do: true
  defp blank?(value, true) when is_float(value) and value == 0.0, do: true
  defp blank?(_, _), do: false

  defp get_raw_action_values_from_notion(page) do
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

  defp get_notion_name(page),
    do: get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])

  defp get_description(page) do
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

  defp extract_page_title(page) do
    props = page["properties"] || %{}
    title_prop = props["Name"] || props["Title"] || props["title"]

    case title_prop do
      %{"title" => [%{"plain_text" => text} | _]} -> text
      _ -> nil
    end
  end

  def fetch_session_notes(query, campaign_id \\ nil) do
    token = get_token(campaign_id)
    search = if String.contains?(query, "session"), do: query, else: "session #{query}"

    res =
      NotionClient.search(search, %{
        "filter" => %{"property" => "object", "value" => "page"},
        :token => token
      })

    case res["results"] do
      [page | _] ->
        blocks = NotionClient.get_block_children(page["id"], token: token)

        {:ok,
         %{
           title: extract_page_title(page),
           content: parse_blocks_to_text(blocks["results"] || [])
         }}

      _ ->
        {:error, :not_found}
    end
  rescue
    e -> {:error, e}
  end

  def fetch_session_by_id(id, campaign_id \\ nil) do
    token = get_token(campaign_id)

    case NotionClient.get_page(id, token: token) do
      %{"id" => _} = page ->
        blocks = NotionClient.get_block_children(id, token: token)

        {:ok,
         %{
           title: extract_page_title(page),
           content: parse_blocks_to_text(blocks["results"] || [])
         }}

      _ ->
        {:error, :not_found}
    end
  rescue
    e -> {:error, e}
  end

  def fetch_adventure(q, campaign_id \\ nil), do: fetch_session_notes(q, campaign_id)
  def fetch_adventure_by_id(id, campaign_id \\ nil), do: fetch_session_by_id(id, campaign_id)

  def fetch_page_content(id, token \\ nil) do
    case NotionClient.get_block_children(id, token: token) do
      %{"results" => blocks} -> {:ok, parse_blocks_to_text(blocks)}
      _ -> {:error, :failed}
    end
  rescue
    _ -> {:error, :failed}
  end

  def parse_blocks_to_text(blocks),
    do: Enum.map(blocks || [], &block_to_text/1) |> Enum.reject(&is_nil/1) |> Enum.join("\n")

  defp block_to_text(%{"type" => "paragraph"} = b),
    do: extract_rich_text(b["paragraph"]["rich_text"])

  defp block_to_text(%{"type" => "heading_1"} = b),
    do: "# " <> extract_rich_text(b["heading_1"]["rich_text"])

  defp block_to_text(%{"type" => "heading_2"} = b),
    do: "## " <> extract_rich_text(b["heading_2"]["rich_text"])

  defp block_to_text(%{"type" => "heading_3"} = b),
    do: "### " <> extract_rich_text(b["heading_3"]["rich_text"])

  defp block_to_text(%{"type" => "bulleted_list_item"} = b),
    do: "- " <> extract_rich_text(b["bulleted_list_item"]["rich_text"])

  defp block_to_text(%{"type" => "numbered_list_item"} = b),
    do: "1. " <> extract_rich_text(b["numbered_list_item"]["rich_text"])

  defp block_to_text(_), do: nil
  defp extract_rich_text(l) when is_list(l), do: Enum.map(l, & &1["plain_text"]) |> Enum.join("")
  defp extract_rich_text(_), do: ""

  defp juncture_as_notion(%Juncture{} = juncture) do
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
    |> Map.put("Locations", %{
      "relation" => Enum.map(location_ids, &%{"id" => &1})
    })
    |> Map.put("People", %{
      "relation" => Enum.map(people_ids, &%{"id" => &1})
    })
  end

  defp set_faction_from_notion(c, p, cid, t) do
    case get_faction_name_from_notion(p, t) do
      nil ->
        {:ok, c}

      name ->
        case find_local_faction_by_name(name, cid) do
          nil -> {:ok, c}
          f -> Characters.update_character(c, %{faction_id: f.id})
        end
    end
  end

  defp set_juncture_from_notion(character, page, campaign_id, _token) do
    case get_juncture_name_from_notion(page) do
      nil ->
        {:ok, character}

      juncture_name ->
        case find_local_juncture_by_name(juncture_name, campaign_id) do
          nil ->
            Logger.debug("No local juncture found for '#{juncture_name}'")
            {:ok, character}

          juncture ->
            Characters.update_character(character, %{juncture_id: juncture.id})
        end
    end
  end

  defp get_faction_name_from_notion(page, token) do
    case get_in(page, ["properties", "Faction", "relation"]) do
      [%{"id" => id} | _] ->
        p = NotionClient.get_page(id, token: token)

        get_in(p, ["properties", "Name", "title", Access.at(0), "plain_text"]) ||
          get_in(p, ["properties", "Name", "rich_text", Access.at(0), "plain_text"])

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp notion_faction_properties(name, cid, token) do
    case find_faction_by_name(name, cid, token) do
      [f | _] -> %{"relation" => [%{"id" => f["id"]}]}
      _ -> nil
    end
  end

  defp get_juncture_name_from_notion(page) do
    case get_in(page, ["properties", "Juncture", "multi_select"]) do
      [%{"name" => juncture_name} | _] -> juncture_name
      _ -> nil
    end
  end

  defp find_local_faction_by_name(name, campaign_id) do
    Repo.one(
      from(f in Faction,
        where: f.name == ^name and f.campaign_id == ^campaign_id,
        limit: 1
      )
    )
  end

  defp find_local_juncture_by_name(name, campaign_id) do
    # First try exact match
    exact_match =
      Repo.one(
        from(j in Juncture,
          where: j.name == ^name and j.campaign_id == ^campaign_id,
          limit: 1
        )
      )

    case exact_match do
      nil ->
        # Try partial match - find junctures that start with the Notion name
        search_pattern = "#{name}%"

        Repo.one(
          from(j in Juncture,
            where: ilike(j.name, ^search_pattern) and j.campaign_id == ^campaign_id,
            order_by: [asc: j.name],
            limit: 1
          )
        )

      juncture ->
        juncture
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

  defp get_checkbox_content(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("checkbox")
  end

  defp get_title_content(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("title", [])
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end

  defp get_entity_name(props) do
    title = get_title_content(props, "Name")

    if title != "" do
      title
    else
      get_rich_text_content(props, "Name")
    end
  end
end
