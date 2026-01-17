defmodule ShotElixir.Services.NotionService do
  @moduledoc """
  Business logic layer for Notion API integration.
  Handles synchronization of characters, sites, parties, factions, and junctures with Notion databases.
  """

  require Logger

  alias ShotElixir.Services.NotionClient
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
  alias ShotElixir.Adventures
  alias ShotElixir.Adventures.Adventure
  alias ShotElixir.Helpers.MentionConverter

  import Ecto.Query

  @data_source_cache_table :notion_data_source_cache

  # =============================================================================
  # Dynamic Notion Integration (OAuth + Campaign-specific Database IDs)
  # =============================================================================
  #
  # Notion integration uses OAuth and campaign-specific settings stored in the database:
  # - campaign.notion_access_token - OAuth token for the campaign's Notion workspace
  # - campaign.notion_database_ids - Map of entity types to Notion database IDs
  #   Example: %{"characters" => "abc123", "sites" => "def456", "adventures" => "ghi789"}
  #
  # This replaces the legacy hardcoded database IDs that were in runtime.exs config.
  # =============================================================================

  alias ShotElixir.Campaigns.Campaign

  @doc """
  Get the Notion API token for a campaign.

  Only the OAuth token stored on the campaign is considered valid. We no longer
  fall back to environment variables or application config for Notion tokens.
  If a campaign is missing an OAuth token, callers should treat that as
  "not configured" and skip syncing.
  """
  def get_token(%Campaign{notion_access_token: token}) when is_binary(token) and token != "" do
    token
  end

  def get_token(_), do: nil

  @doc """
  Get Notion database ID for an entity type from campaign settings.

  Returns {:ok, database_id} or {:error, :no_database_configured}.

  ## Entity Types
  - "characters" - Character database
  - "sites" - Sites/Locations database
  - "parties" - Parties database
  - "factions" - Factions database
  - "junctures" - Junctures/Time periods database
  - "adventures" - Adventures database
  """
  def get_database_id_for_entity(%Campaign{notion_database_ids: nil}, entity_type) do
    Logger.warning("Campaign has no notion_database_ids configured for #{entity_type}")
    {:error, :no_database_configured}
  end

  def get_database_id_for_entity(%Campaign{notion_database_ids: db_ids}, entity_type)
      when is_map(db_ids) do
    case Map.get(db_ids, entity_type) do
      nil ->
        Logger.warning("No Notion database ID configured for #{entity_type}")
        {:error, :no_database_configured}

      database_id when is_binary(database_id) ->
        {:ok, database_id}
    end
  end

  def get_database_id_for_entity(_campaign, entity_type) do
    Logger.warning("Invalid campaign or notion_database_ids for #{entity_type}")
    {:error, :no_database_configured}
  end

  @doc false
  def init_data_source_cache do
    _ = data_source_cache_table()
    :ok
  end

  defp data_source_cache_table do
    case :ets.whereis(@data_source_cache_table) do
      :undefined ->
        try do
          :ets.new(@data_source_cache_table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true
          ])
        rescue
          ArgumentError -> @data_source_cache_table
        end

      _ ->
        @data_source_cache_table
    end
  end

  defp cached_data_source_id(database_id) do
    table = data_source_cache_table()

    case :ets.lookup(table, database_id) do
      [{^database_id, data_source_id}] -> {:ok, data_source_id}
      _ -> :miss
    end
  end

  defp cache_data_source_id(database_id, data_source_id) do
    table = data_source_cache_table()
    :ets.insert(table, {database_id, data_source_id})
    :ok
  end

  defp extract_data_source_id(data_sources) do
    # Notion returns a list of data source objects; tests may pass raw IDs.
    Enum.find_value(data_sources, fn
      %{"id" => id} when is_binary(id) -> id
      id when is_binary(id) -> id
      _ -> nil
    end)
  end

  defp data_source_id_for(database_id, opts) do
    case cached_data_source_id(database_id) do
      {:ok, data_source_id} ->
        {:ok, data_source_id}

      :miss ->
        client = notion_client(opts)
        token = Keyword.get(opts, :token)

        case client.get_database(database_id, %{token: token}) do
          # 2025-09-03 returns data_sources as a list of objects.
          %{"data_sources" => data_sources} when is_list(data_sources) ->
            case extract_data_source_id(data_sources) do
              nil ->
                {:error, :notion_data_source_missing}

              data_source_id ->
                cache_data_source_id(database_id, data_source_id)
                {:ok, data_source_id}
            end

          # Older responses may include a single data_source_id or data_source object.
          %{"data_source_id" => data_source_id} when is_binary(data_source_id) ->
            cache_data_source_id(database_id, data_source_id)
            {:ok, data_source_id}

          %{"data_source" => %{"id" => data_source_id}} when is_binary(data_source_id) ->
            cache_data_source_id(database_id, data_source_id)
            {:ok, data_source_id}

          %{"code" => error_code, "message" => message} ->
            Logger.error(
              "Notion get_database error for database_id=#{database_id}: " <>
                "#{error_code} - #{message}"
            )

            {:error, {:notion_api_error, error_code, message}}

          nil ->
            Logger.error("Notion get_database returned nil for database_id=#{database_id}")
            {:error, :notion_database_not_found}

          response ->
            Logger.error(
              "Unexpected response from Notion get_database for database_id=#{database_id}: " <>
                "#{inspect(response)}"
            )

            {:error, {:unexpected_notion_response, response}}
        end
    end
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
      # Unlinked pages should not update the sync timestamp
      {:ok, :unlinked} ->
        {:ok, :unlinked}

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
      Logger.error("Exception syncing character to Notion: #{Exception.message(error)}")
      {:error, error}
  end

  @doc """
  Perform a smart two-way merge when linking a character to a Notion page.

  Merge rules:
  - If one side is blank and the other has a value → use the value
  - If both have values → keep both as-is (no overwrite)
  - For action values: 0 is treated as blank (can be overwritten by non-zero)

  This updates both the Chi War record and the Notion page with merged values.
  """
  def merge_with_notion(%Character{} = character, notion_page_id) do
    character = Repo.preload(character, [:faction, :campaign])
    token = get_token(character.campaign)

    if is_nil(token) do
      Logger.warning("Notion merge skipped: campaign missing OAuth token")
      {:error, :no_notion_oauth_token}
    else
      case NotionClient.get_page(notion_page_id, %{token: token}) do
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
            smart_merge_description(
              character.description || %{},
              notion_description
            )

          merged_name =
            if blank?(character.name),
              do: notion_name || character.name,
              else: character.name

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

              case update_notion_from_character(updated_character) do
                {:ok, _} ->
                  :ok

                {:error, reason} ->
                  Logger.warning(
                    "Failed to update Notion after merge for character #{updated_character.id}: #{inspect(reason)}"
                  )

                other ->
                  Logger.warning(
                    "Unexpected response when updating Notion after merge for character #{updated_character.id}: #{inspect(other)}"
                  )
              end

              updated_character =
                if is_nil(updated_character.faction_id) do
                  case set_faction_from_notion(
                         updated_character,
                         page,
                         updated_character.campaign_id,
                         token
                       ) do
                    {:ok, char} -> char
                    {:error, _} -> updated_character
                  end
                else
                  updated_character
                end

              updated_character =
                if is_nil(updated_character.juncture_id) do
                  case set_juncture_from_notion(
                         updated_character,
                         page,
                         updated_character.campaign_id
                       ) do
                    {:ok, char} -> char
                    {:error, _} -> updated_character
                  end
                else
                  updated_character
                end

              add_image(page, updated_character, token: token)
              Notion.log_success("character", updated_character.id, %{action: "merge"}, page)
              {:ok, updated_character}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end
  rescue
    error ->
      Logger.error("Exception merging with Notion: #{Exception.message(error)}")
      {:error, error}
  end

  # Smart merge for action_values - handles 0 as blank
  defp smart_merge_action_values(local, notion) do
    all_keys =
      MapSet.union(
        MapSet.new(Map.keys(local)),
        MapSet.new(Map.keys(notion))
      )

    Enum.reduce(all_keys, %{}, fn key, acc ->
      local_val = Map.get(local, key)
      notion_val = Map.get(notion, key)

      merged_val = smart_merge_value(local_val, notion_val, action_value?: true)
      Map.put(acc, key, merged_val)
    end)
  end

  # Smart merge for description - handles empty strings as blank
  defp smart_merge_description(local, notion) do
    all_keys =
      MapSet.union(
        MapSet.new(Map.keys(local)),
        MapSet.new(Map.keys(notion))
      )

    Enum.reduce(all_keys, %{}, fn key, acc ->
      local_val = Map.get(local, key)
      notion_val = Map.get(notion, key)

      merged_val = smart_merge_value(local_val, notion_val, action_value?: false)
      Map.put(acc, key, merged_val)
    end)
  end

  # Core merge logic for a single value
  # Rules:
  # - If both blank → keep local (nil)
  # - If local blank, notion has value → use notion
  # - If notion blank, local has value → keep local
  # - If both have values → keep local (don't overwrite)
  defp smart_merge_value(local_val, notion_val, opts) do
    is_action_value = Keyword.get(opts, :action_value?, false)
    local_blank = blank?(local_val, is_action_value)
    notion_blank = blank?(notion_val, is_action_value)

    cond do
      local_blank and notion_blank -> local_val
      local_blank and not notion_blank -> notion_val
      not local_blank and notion_blank -> local_val
      # Both have values - keep local (no overwrite)
      true -> local_val
    end
  end

  # Check if a value is considered "blank"
  # For action values: nil, "", or 0 are blank
  # For other values: nil or "" are blank
  defp blank?(value, is_action_value \\ false)
  defp blank?(nil, _), do: true
  defp blank?("", _), do: true
  defp blank?(0, true), do: true
  defp blank?("0", true), do: true
  defp blank?(value, true) when is_float(value) and value == 0.0, do: true
  defp blank?(_, _), do: false

  @doc """
  Create a new Notion page from character data.
  """
  def create_notion_from_character(%Character{} = character) do
    # Ensure faction and campaign are loaded for Notion properties and database ID
    character = Repo.preload(character, [:faction, :campaign])
    token = get_token(character.campaign)

    if is_nil(token) do
      Logger.warning("Notion sync skipped: campaign missing OAuth token")
      Notion.log_error("character", character.id, %{}, %{}, "Notion OAuth token missing")
      {:error, :no_notion_oauth_token}
    else
      properties = Character.as_notion(character)

      properties =
        if character.faction do
          faction_props = notion_faction_properties(character.campaign, character.faction.name)
          # Only add Faction if we found a matching faction in Notion
          if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
        else
          properties
        end

      with {:ok, database_id} <- get_database_id_for_entity(character.campaign, "characters"),
           {:ok, data_source_id} <- data_source_id_for(database_id, token: token) do
        Logger.debug("Creating Notion page with data_source_id: #{data_source_id}")

        # Capture payload for logging
        payload = %{
          "parent" => %{"data_source_id" => data_source_id},
          "properties" => properties,
          token: token
        }

        page = NotionClient.create_page(payload)

        Logger.debug("Notion API response received")

        # Check if Notion returned an error response
        case page do
          %{"id" => page_id} when is_binary(page_id) ->
            Logger.debug("Extracted page ID: #{inspect(page_id)}")

            # Log successful sync
            Notion.log_success("character", character.id, payload, page)

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
              "character",
              character.id,
              payload,
              page,
              "Notion API error: #{error_code} - #{message}"
            )

            {:error, {:notion_api_error, error_code, message}}

          _ ->
            Logger.error("Unexpected response from Notion API")
            # Log error sync
            Notion.log_error(
              "character",
              character.id,
              payload,
              page,
              "Unexpected response from Notion API"
            )

            {:error, :unexpected_notion_response}
        end
      else
        {:error, reason} ->
          Logger.error("Failed to resolve Notion data source for characters: #{inspect(reason)}")

          Notion.log_error(
            "character",
            character.id,
            %{},
            %{},
            "Notion data source lookup failed: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  rescue
    error ->
      # Avoid logging potentially sensitive HTTP request metadata
      Logger.error("Failed to create Notion page: #{Exception.message(error)}")
      # Log error sync (with nil payload since we may not have gotten there)
      Notion.log_error(
        "character",
        character.id,
        %{},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, :notion_request_failed}
  end

  @doc """
  Update existing Notion page with character data.
  """
  def update_notion_from_character(%Character{notion_page_id: nil}), do: {:error, :no_page_id}

  def update_notion_from_character(%Character{} = character) do
    # Ensure campaign and faction are loaded for faction properties lookup
    character = Repo.preload(character, [:campaign, :faction])
    token = get_token(character.campaign)

    if is_nil(token) do
      Logger.warning("Notion sync skipped: campaign missing OAuth token")
      Notion.log_error("character", character.id, %{}, %{}, "Notion OAuth token missing")
      {:error, :no_notion_oauth_token}
    else
      try do
        properties = Character.as_notion(character)

        properties =
          if character.faction do
            faction_props = notion_faction_properties(character.campaign, character.faction.name)
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

        response = NotionClient.update_page(character.notion_page_id, properties, %{token: token})

        # Check if Notion returned an error response
        case response do
          # Handle archived/deleted page - unlink from character
          %{"code" => "validation_error", "message" => message}
          when is_binary(message) ->
            if String.contains?(String.downcase(message), "archived") do
              handle_archived_page(character, payload, response, message)
            else
              # Other validation errors - log and return error
              Logger.error("Notion API validation error on update: #{message}")

              Notion.log_error(
                "character",
                character.id,
                payload,
                response,
                "Notion API error: validation_error - #{message}"
              )

              {:error, {:notion_api_error, "validation_error", message}}
            end

          # Handle object_not_found - page was deleted, unlink from character
          %{"code" => "object_not_found", "message" => message} ->
            handle_archived_page(character, payload, response, message)

          %{"code" => error_code, "message" => message} ->
            Logger.error("Notion API error on update: #{error_code}")

            Notion.log_error(
              "character",
              character.id,
              payload,
              response,
              "Notion API error: #{error_code} - #{message}"
            )

            {:error, {:notion_api_error, error_code, message}}

          _ ->
            # Add image if not present in Notion
            page = NotionClient.get_page(character.notion_page_id, %{token: token})
            image = find_image_block(page, token: token)

            unless image do
              add_image_to_notion(character)
            end

            # Log successful sync
            Notion.log_success("character", character.id, payload, response || page)

            {:ok, page}
        end
      rescue
        error ->
          Logger.error("Failed to update Notion page: #{Exception.message(error)}")
          # Log error sync
          Notion.log_error(
            "character",
            character.id,
            %{"page_id" => character.notion_page_id},
            %{},
            "Exception: #{Exception.message(error)}"
          )

          {:error, error}
      end
    end
  end

  @doc """
  Create a new character from Notion page data.
  Always creates a new character. If a character with the same name exists,
  generates a unique name (e.g., "Character Name (1)") to avoid conflicts.

  Also imports:
  - Faction (from Notion relation, matched by name to local faction)
  - Juncture (from Notion multi_select, matched by name to local juncture)
  - Fortune and other action values
  """
  def create_character_from_notion(page, campaign_id, token \\ nil) do
    name = get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])

    # Generate unique name to avoid overwriting existing characters
    # If "Hero" exists, this will return "Hero (1)"
    unique_name = Characters.generate_unique_name(name, campaign_id)

    # Always create a new character for imports from Notion
    {:ok, character} = Characters.create_character(%{name: unique_name, campaign_id: campaign_id})

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

    # Look up and set faction from Notion relation
    {:ok, character} = set_faction_from_notion(character, page, campaign_id, token)

    # Look up and set juncture from Notion multi_select
    {:ok, character} = set_juncture_from_notion(character, page, campaign_id)

    # Add image if not already present
    add_image(page, character, token: token)

    {:ok, character}
  rescue
    error ->
      Logger.error("Failed to create character from Notion: #{Exception.message(error)}")
      {:error, error}
  end

  # Look up faction from Notion relation and set on character
  defp set_faction_from_notion(character, page, campaign_id, token) do
    case get_faction_name_from_notion(page, token) do
      nil ->
        {:ok, character}

      faction_name ->
        case find_local_faction_by_name(faction_name, campaign_id) do
          nil ->
            Logger.debug("No local faction found for '#{faction_name}'")
            {:ok, character}

          faction ->
            Characters.update_character(character, %{faction_id: faction.id})
        end
    end
  end

  # Look up juncture from Notion multi_select and set on character
  defp set_juncture_from_notion(character, page, campaign_id) do
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

  # Get faction name from Notion relation by fetching the related page
  defp get_faction_name_from_notion(page, token) do
    case get_in(page, ["properties", "Faction", "relation"]) do
      [%{"id" => faction_page_id} | _] ->
        faction_page = NotionClient.get_page(faction_page_id, %{token: token})

        # Faction pages use rich_text for Name, not title
        get_in(faction_page, ["properties", "Name", "rich_text", Access.at(0), "plain_text"]) ||
          get_in(faction_page, ["properties", "Name", "title", Access.at(0), "plain_text"])

      _ ->
        nil
    end
  rescue
    error ->
      Logger.warning("Failed to fetch faction from Notion: #{Exception.message(error)}")
      nil
  end

  # Get juncture name from Notion multi_select (takes first value)
  defp get_juncture_name_from_notion(page) do
    case get_in(page, ["properties", "Juncture", "multi_select"]) do
      [%{"name" => juncture_name} | _] -> juncture_name
      _ -> nil
    end
  end

  # Find a local faction by name in the campaign
  defp find_local_faction_by_name(name, campaign_id) do
    Repo.one(
      from(f in Faction,
        where: f.name == ^name and f.campaign_id == ^campaign_id,
        limit: 1
      )
    )
  end

  # Find a local juncture by name in the campaign
  # Uses partial matching - "Past" matches "Past 1870"
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

  @doc """
  Update character from Notion page data.
  """
  def update_character_from_notion(character, opts \\ [])

  def update_character_from_notion(%Character{notion_page_id: nil}, _opts),
    do: {:error, :no_page_id}

  def update_character_from_notion(%Character{} = character, opts) do
    payload = %{"page_id" => character.notion_page_id}
    token = get_token(character.campaign)

    if is_nil(token) do
      Logger.warning("Notion inbound sync skipped: campaign missing OAuth token")
      log_sync_error("character", character.id, payload, %{}, "Notion OAuth token missing")
      {:error, :no_notion_oauth_token}
    else
      client = notion_client(Keyword.merge(opts, token: token))

      case client.get_page(character.notion_page_id, %{token: token}) do
        # Defensive check: Req.get! typically raises on failure, but we handle
        # the unlikely case of a nil body for robustness
        nil ->
          Logger.error("Failed to fetch Notion page: #{character.notion_page_id}")
          log_sync_error("character", character.id, payload, %{}, "Notion page not found")
          {:error, :notion_page_not_found}

        # Handle Notion API error responses (e.g., page not found, unauthorized)
        %{"code" => error_code, "message" => message} = response ->
          Logger.error("Notion API error: #{error_code} - #{message}")

          log_sync_error(
            "character",
            character.id,
            payload,
            response,
            "Notion API error: #{error_code} - #{message}"
          )

          {:error, {:notion_api_error, error_code, message}}

        # Success case: page data returned as a map
        page when is_map(page) ->
          attributes = Character.attributes_from_notion(character, page)

          # Fetch rich description from page content (blocks)
          attributes =
            add_rich_description(
              attributes,
              character.notion_page_id,
              character.campaign_id,
              token
            )

          # Add image if not already present
          add_image(page, character, token: token)

          # Skip Notion sync to prevent ping-pong loops when updating from webhook
          case Characters.update_character(character, attributes, skip_notion_sync: true) do
            {:ok, updated_character} = result ->
              Notion.log_success("character", updated_character.id, payload, page)
              result

            {:error, changeset} = error ->
              log_sync_error(
                "character",
                character.id,
                payload,
                page,
                "Failed to update character from Notion: #{inspect(changeset)}"
              )

              error
          end
      end
    end
  rescue
    error ->
      Logger.error("Failed to update character from Notion: #{Exception.message(error)}")

      log_sync_error(
        "character",
        character.id,
        %{"page_id" => character.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  @doc """
  Handle archived/deleted Notion page by unlinking from character.
  Clears the notion_page_id so future syncs will create a new page.
  Returns {:ok, :unlinked} to signal success (so Oban worker doesn't retry).
  """
  def handle_archived_page(%Character{} = character, payload, response, message) do
    Logger.warning(
      "Notion page #{character.notion_page_id} for character #{character.id} " <>
        "has been archived/deleted. Unlinking from character."
    )

    # Log the unlink event (as a special "unlinked" status or error with context)
    Notion.log_error(
      "character",
      character.id,
      payload,
      response,
      "Notion page archived/deleted - unlinking from character: #{message}"
    )

    # Clear the notion_page_id from the character
    case Characters.update_character(character, %{notion_page_id: nil}) do
      {:ok, _updated_character} ->
        Logger.info("Successfully unlinked Notion page from character #{character.id}")
        {:ok, :unlinked}

      {:error, changeset} ->
        Logger.error("Failed to unlink Notion page from character: #{inspect(changeset)}")
        {:error, {:unlink_failed, changeset}}
    end
  end

  @doc """
  Search for Notion pages by name across all accessible pages.

  ## Parameters
    * `name` - The name to search for

  ## Returns
    * List of matching Notion pages with id, title/name, and url
  """
  def find_page_by_name(name) do
    results =
      NotionClient.search(name, %{
        "filter" => %{"property" => "object", "value" => "page"}
      })

    case results do
      # Handle Notion API error responses
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion search error: #{error_code} - #{message}")
        []

      # Success case: results map containing a list under "results"
      %{"results" => pages} when is_list(pages) ->
        Enum.map(pages, fn page ->
          %{
            "id" => page["id"],
            "title" => extract_page_title(page),
            "url" => page["url"]
          }
        end)

      # Any other response (nil, missing results key, etc.)
      _ ->
        Logger.warning("Unexpected response from Notion search: #{inspect(results)}")
        []
    end
  rescue
    error ->
      Logger.error("Failed to search Notion pages: #{Exception.message(error)}")
      []
  end

  @doc """
  Search for pages in a Notion data source by name.

  In Notion API 2025-09-03, the search API with filter "data_source" returns
  data_source IDs (not database IDs). This function expects a data_source_id
  and queries it directly.

  ## Parameters
    * `data_source_id` - The Notion data source ID (from search API with "data_source" filter)
    * `name` - The name to search for (partial match, case-insensitive)
    * `opts` - Options including `:token` for OAuth authentication

  ## Returns
    * List of matching Notion pages with id, title, and url
  """
  def find_pages_in_database(data_source_id, name, opts \\ []) do
    # In Notion API 2025-09-03, IDs from search with filter "data_source" are already
    # data_source IDs. Use them directly with data_source_query instead of calling
    # get_database (which expects a database ID, not a data_source ID).
    filter =
      if name == "" do
        %{}
      else
        %{
          "filter" => %{
            "property" => "Name",
            "title" => %{"contains" => name}
          }
        }
      end

    client = notion_client(opts)
    token = Keyword.get(opts, :token)
    query_opts = Map.put(filter, :token, token)
    response = client.data_source_query(data_source_id, query_opts)

    case response do
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion data_source_query error: #{error_code} - #{message}")
        []

      %{"results" => pages} when is_list(pages) ->
        Enum.map(pages, fn page ->
          %{
            "id" => page["id"],
            "title" => extract_page_title(page),
            "url" => page["url"]
          }
        end)

      _ ->
        Logger.warning("Unexpected response from Notion data_source_query: #{inspect(response)}")
        []
    end
  rescue
    error ->
      Logger.error("Failed to query Notion database: #{Exception.message(error)}")
      []
  end

  # NOTE: Legacy search functions (find_sites_in_notion, find_parties_in_notion, etc.)
  # have been removed. They were unused and relied on legacy hardcoded database IDs.
  # If needed in the future, they should be reimplemented to accept a campaign parameter
  # and use get_database_id_for_entity/2 for dynamic database ID lookup.

  @doc """
  Find faction in Notion by name.

  ## Parameters
    * `campaign` - The campaign struct with notion_database_ids
    * `name` - The faction name to search for
    * `opts` - Additional options (e.g., :token)

  ## Returns
    * List of matching faction pages (empty list if not found or no database configured)
  """
  def find_faction_by_name(campaign, name, opts \\ [])

  def find_faction_by_name(nil, _name, _opts), do: []

  def find_faction_by_name(%Campaign{} = campaign, name, opts) do
    filter = %{
      "and" => [
        %{
          "property" => "Name",
          "rich_text" => %{"equals" => name}
        }
      ]
    }

    with {:ok, database_id} <- get_database_id_for_entity(campaign, "factions"),
         {:ok, data_source_id} <- data_source_id_for(database_id, opts) do
      client = notion_client(opts)
      # Extract token from opts and pass to data_source_query
      token = Keyword.get(opts, :token)
      query_opts = Map.put(%{"filter" => filter}, :token, token)
      response = client.data_source_query(data_source_id, query_opts)
      response["results"] || []
    else
      {:error, reason} ->
        Logger.error("Failed to resolve Notion data source for factions: #{inspect(reason)}")
        []
    end
  end

  @doc """
  Find image block in Notion page.
  Handles pagination to check all blocks, not just the first page.

  ## Parameters
    * `page` - Notion page with "id" field

  ## Returns
    * Image block if found, nil otherwise
  """
  def find_image_block(page, opts \\ []) do
    client = Keyword.get(opts, :client, NotionClient)
    token = Keyword.get(opts, :token)
    find_image_block_paginated(page["id"], nil, client, token)
  end

  defp find_image_block_paginated(page_id, start_cursor, client, token) do
    response = client.get_block_children(page_id, %{start_cursor: start_cursor, token: token})
    results = response["results"] || []

    # Check if there's an image in this page of results
    case Enum.find(results, fn block -> block["type"] == "image" end) do
      nil ->
        # No image found in this page - check if there are more pages
        if response["has_more"] do
          find_image_block_paginated(page_id, response["next_cursor"], client, token)
        else
          nil
        end

      image_block ->
        image_block
    end
  end

  @doc """
  Add image to Notion page from entity.
  """
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

  @doc """
  Add image from Notion to character.
  Downloads image from Notion and uploads to ImageKit, then attaches to character.

  Returns `{:ok, result}` on success (including when skipped), `{:error, reason}` on failure.

  Note: Notion file URLs (type "file") expire after approximately 1 hour.
  This function should be called immediately after extracting the URL from Notion,
  not in a delayed or asynchronous context.
  """
  def add_image(page, %Character{} = character, opts \\ []) do
    # Check if character already has an image via ActiveStorage
    existing_image_url = ShotElixir.ActiveStorage.get_image_url("Character", character.id)

    if existing_image_url do
      {:ok, :skipped_existing_image}
    else
      case find_image_block(page, opts) do
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
    # Validate URL to prevent SSRF attacks
    case validate_image_url(url) do
      :ok ->
        do_download_with_temp_file(url, character)

      {:error, reason} ->
        Logger.warning("Rejected image URL for SSRF protection: #{inspect(reason)}")
        {:error, {:invalid_url, reason}}
    end
  end

  # SSRF protection: Only allow downloads from trusted image sources
  @trusted_image_domains [
    # Notion's file storage
    ~r/^prod-files-secure\.s3\.us-west-2\.amazonaws\.com$/,
    ~r/^s3\.us-west-2\.amazonaws\.com$/,
    # Notion hosted images
    ~r/^.*\.notion\.so$/,
    ~r/^.*\.notion-static\.com$/,
    # Common image CDNs used in Notion
    ~r/^images\.unsplash\.com$/,
    ~r/^.*\.cloudfront\.net$/
  ]

  defp validate_image_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      # Must be HTTPS
      uri.scheme != "https" ->
        {:error, :not_https}

      # Must have a host
      is_nil(uri.host) ->
        {:error, :no_host}

      # Host must match trusted domains
      not trusted_domain?(uri.host) ->
        {:error, :untrusted_domain}

      # Prevent localhost/internal IPs
      internal_address?(uri.host) ->
        {:error, :internal_address}

      true ->
        :ok
    end
  end

  defp validate_image_url(_), do: {:error, :invalid_url}

  defp trusted_domain?(host) do
    Enum.any?(@trusted_image_domains, fn pattern ->
      Regex.match?(pattern, host)
    end)
  end

  defp internal_address?(host) do
    # Block localhost and private IP ranges
    host in ["localhost", "127.0.0.1", "0.0.0.0"] or
      String.starts_with?(host, "192.168.") or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "172.16.") or
      String.starts_with?(host, "169.254.") or
      String.ends_with?(host, ".local") or
      String.ends_with?(host, ".internal")
  end

  defp do_download_with_temp_file(url, character) do
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
      Logger.error("Exception downloading Notion image: #{Exception.message(error)}")
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
    # Upload to ImageKit with AI auto-tagging
    case ShotElixir.Services.ImagekitService.upload_file(final_path, %{
           folder: "/chi-war-#{Mix.env()}/characters",
           file_name: "#{character.id}#{extension}",
           auto_tag: true,
           max_tags: 10,
           min_confidence: 70
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

  # Extract raw action values from Notion page without any merge logic
  # This gets the actual Notion values for proper two-way merge
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
    # Filter out nil values so they don't interfere with merge
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Extract name from Notion page
  defp get_notion_name(page) do
    get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])
  end

  # Get select value from Notion properties
  defp get_select_content(props, key) do
    case get_in(props, [key, "select"]) do
      %{"name" => name} -> name
      _ -> nil
    end
  end

  # Get number value from Notion properties
  defp get_number_content(props, key) do
    get_in(props, [key, "number"])
  end

  # Get date value from Notion properties (parses ISO8601 to DateTime)
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

  defp notion_faction_properties(campaign, name) do
    case find_faction_by_name(campaign, name) do
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

  defp notion_client(opts), do: Keyword.get(opts, :client, NotionClient)

  defp log_sync_error(entity_type, entity_id, payload, response, message) do
    Notion.log_error(entity_type, entity_id, payload, response, message)
  end

  # Version with mention conversion support
  defp entity_attributes_from_notion(page, campaign_id) do
    props = page["properties"] || %{}

    %{
      notion_page_id: page["id"],
      name: get_entity_name(props),
      description: get_rich_text_as_html(props, "Description", campaign_id)
    }
    |> maybe_put_at_a_glance(get_checkbox_content(props, "At a Glance"))
  end

  # Adventure-specific version with additional fields (season, started_at, ended_at)
  defp adventure_attributes_from_notion(page, campaign_id) do
    props = page["properties"] || %{}

    entity_attributes_from_notion(page, campaign_id)
    |> Map.put(:last_synced_to_notion_at, DateTime.utc_now())
    |> maybe_put_if_not_nil(:season, get_number_content(props, "Season"))
    |> maybe_put_if_not_nil(:started_at, get_date_content(props, "Started"))
    |> maybe_put_if_not_nil(:ended_at, get_date_content(props, "Ended"))
  end

  defp maybe_put_if_not_nil(map, _key, nil), do: map
  defp maybe_put_if_not_nil(map, key, value), do: Map.put(map, key, value)

  # Fetch rich description from page content and add to attributes
  defp add_rich_description(attributes, page_id, campaign_id, token) do
    case fetch_rich_description(page_id, campaign_id, token) do
      {:ok, %{markdown: markdown, mentions: mentions}} ->
        attributes
        |> Map.put(:rich_description, markdown)
        |> Map.put(:mentions, mentions)

      {:error, reason} ->
        Logger.warning("Failed to fetch rich description for page #{page_id}: #{inspect(reason)}")
        attributes
    end
  end

  # Backwards-compatible arity without token (falls back to nil token)
  defp add_rich_description(attributes, page_id, campaign_id),
    do: add_rich_description(attributes, page_id, campaign_id, nil)

  # Convert Notion rich_text to Chi War HTML with mention support
  defp get_rich_text_as_html(props, key, campaign_id) do
    rich_text =
      props
      |> Map.get(key, %{})
      |> Map.get("rich_text", [])

    MentionConverter.notion_rich_text_to_html(rich_text, campaign_id)
  end

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

  defp character_ids_from_notion(page, campaign_id) do
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

  defp site_ids_from_notion(page, campaign_id) do
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

  defp get_entity_name(props) do
    title = get_title_content(props, "Name")

    if title != "" do
      title
    else
      get_rich_text_content(props, "Name")
    end
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

  # =============================================================================
  # Session Notes Functions
  # =============================================================================

  # Extracts the title from a Notion page's properties.
  # Tries both "title" and "Name" property keys since Notion pages can use either.
  defp extract_page_title(page) do
    props = page["properties"] || %{}

    # Try common title property names
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

  @doc """
  Search for session notes pages in Notion.

  ## Parameters
    * `query` - Search query (e.g., "session 5-10" or "5-10")

  ## Returns
    * `{:ok, %{pages: [...], content: "..."}}` with matching pages and content of first match
    * `{:error, :not_found}` if no pages match
  """
  def fetch_session_notes(query, token) do
    if is_nil(token) do
      Logger.warning("Session search skipped: missing Notion OAuth token")
      {:error, :no_notion_oauth_token}
    else
      search_query = if String.contains?(query, "session"), do: query, else: "session #{query}"

      try do
        results =
          NotionClient.search(search_query, %{
            "filter" => %{"property" => "object", "value" => "page"},
            token: token
          })

        case results["results"] do
          [page | _rest] = pages ->
            # Fetch content of the first (most relevant) match
            blocks = NotionClient.get_block_children(page["id"], %{token: token})
            content = parse_blocks_to_text(blocks["results"] || [])

            {:ok,
             %{
               title: extract_page_title(page),
               page_id: page["id"],
               content: content,
               pages: Enum.map(pages, fn p -> %{id: p["id"], title: extract_page_title(p)} end)
             }}

          [] ->
            {:error, :not_found}

          nil ->
            {:error, :not_found}
        end
      rescue
        error ->
          Logger.error(
            "Failed to fetch session notes for query=#{inspect(query)}: " <>
              Exception.format(:error, error, __STACKTRACE__)
          )

          {:error, error}
      end
    end
  end

  @doc """
  Fetch a specific session page by ID.
  """
  def fetch_session_by_id(page_id, token) do
    if is_nil(token) do
      Logger.warning("Session fetch skipped: missing Notion OAuth token")
      {:error, :no_notion_oauth_token}
    else
      page = NotionClient.get_page(page_id, %{token: token})

      case page do
        %{"id" => _id} ->
          blocks = NotionClient.get_block_children(page_id, %{token: token})
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

  @doc """
  Parse Notion blocks into plain text/markdown.
  """
  def parse_blocks_to_text(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(&parse_block/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def parse_blocks_to_text(_), do: ""

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
    # Intentionally always use "1." to leverage Markdown auto-numbering.
    # This keeps list numbering correct even if items are inserted or removed.
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

  defp parse_block(%{"type" => "child_page"} = block) do
    title = block["child_page"]["title"]
    "📄 #{title}"
  end

  defp parse_block(%{"type" => "child_database"} = block) do
    title = block["child_database"]["title"]
    "📊 #{title}"
  end

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

      # Handle mentions (linked pages)
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

  # =============================================================================
  # Adventure Functions
  # =============================================================================

  @doc """
  Search for adventure pages in Notion by query.
  Returns matching pages with their titles and IDs.

  ## Parameters
    * `query` - The search query string

  ## Returns
    * `{:ok, %{pages: [...], title: ..., page_id: ..., content: ...}}` on success
    * `{:error, reason}` on failure
  """
  def fetch_adventure(query, token) do
    if is_nil(token) do
      Logger.warning("Adventure fetch skipped: missing Notion OAuth token")
      {:error, :no_notion_oauth_token}
    else
      try do
        # Search Notion for pages matching the query
        response =
          NotionClient.search(query, %{
            "filter" => %{"property" => "object", "value" => "page"},
            token: token
          })

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
            # Fetch content for the first matching page
            case fetch_page_content(first.id, token) do
              {:ok, content} ->
                {:ok,
                 %{
                   pages: pages,
                   title: first.title,
                   page_id: first.id,
                   content: content
                 }}

              {:error, reason} ->
                {:error, reason}
            end
        end
      rescue
        error ->
          Logger.error("Failed to search adventures: #{Exception.message(error)}")
          {:error, error}
      end
    end
  end

  @doc """
  Fetch a specific adventure page by its Notion page ID.

  ## Parameters
    * `page_id` - The Notion page ID

  ## Returns
    * `{:ok, %{title: ..., page_id: ..., content: ...}}` on success
    * `{:error, reason}` on failure
  """
  def fetch_adventure_by_id(page_id, token) do
    if is_nil(token) do
      Logger.warning("Adventure fetch skipped: missing Notion OAuth token")
      {:error, :no_notion_oauth_token}
    else
      try do
        page = NotionClient.get_page(page_id, %{token: token})

        case page do
          %{"code" => error_code, "message" => message} ->
            {:error, {:notion_api_error, error_code, message}}

          %{"id" => id} ->
            title = extract_page_title(page)

            case fetch_page_content(id, token) do
              {:ok, content} ->
                {:ok,
                 %{
                   title: title,
                   page_id: id,
                   content: content
                 }}

              {:error, reason} ->
                {:error, reason}
            end

          _ ->
            {:error, :unexpected_notion_response}
        end
      rescue
        error ->
          Logger.error("Failed to fetch adventure by ID: #{Exception.message(error)}")
          {:error, error}
      end
    end
  end

  @doc """
  Fetch page content (blocks) and convert to plain text.
  """
  def fetch_page_content(page_id, token) do
    response = NotionClient.get_block_children(page_id, %{token: token})

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

  @doc """
  Fetch page content (blocks) and convert to markdown with mention resolution.
  Returns `{:ok, %{markdown: string, mentions: map}}` or `{:error, reason}`.

  Mentions are resolved to the format `[[@entity_type:uuid|Display Name]]` for
  later rendering as clickable links in the frontend.

  The mentions map contains resolved entity IDs for quick lookup:
  `%{"character" => [uuid1, uuid2], "site" => [uuid3]}`
  """
  def fetch_rich_description(page_id, campaign_id, token) do
    response = NotionClient.get_block_children(page_id, %{token: token})

    case response do
      %{"results" => blocks} when is_list(blocks) ->
        {markdown, mentions} = blocks_to_markdown_with_mentions(blocks, campaign_id)
        {:ok, %{markdown: markdown, mentions: mentions}}

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

  # Convert Notion blocks to markdown with mention resolution
  defp blocks_to_markdown_with_mentions(blocks, campaign_id) do
    # Accumulate markdown text and collect mentions
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

  # Convert a single block to markdown with mentions
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

      # Skip image blocks - Notion uses temporary signed URLs that expire
      # See Fizzy card for future implementation to re-host images
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

  # Extract rich text with mention resolution
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

  # Convert a single rich text item to markdown, handling mentions
  defp rich_text_item_to_markdown(
         %{"type" => "mention", "mention" => mention} = item,
         campaign_id
       ) do
    case mention do
      %{"type" => "page", "page" => %{"id" => page_id}} ->
        # This is a page mention - try to resolve it to an entity
        resolve_page_mention(page_id, item["plain_text"] || "Unknown", campaign_id)

      %{"type" => "user"} ->
        # User mention - just use the plain text
        {item["plain_text"] || "@User", %{}}

      %{"type" => "date"} ->
        # Date mention
        {item["plain_text"] || "", %{}}

      %{"type" => "database"} ->
        # Database mention
        {item["plain_text"] || "[Database]", %{}}

      _ ->
        {item["plain_text"] || "", %{}}
    end
  end

  defp rich_text_item_to_markdown(%{"type" => "text"} = item, _campaign_id) do
    text = get_in(item, ["text", "content"]) || ""
    annotations = item["annotations"] || %{}

    # Apply markdown formatting based on annotations
    formatted =
      text
      |> maybe_apply_bold(annotations["bold"])
      |> maybe_apply_italic(annotations["italic"])
      |> maybe_apply_strikethrough(annotations["strikethrough"])
      |> maybe_apply_code(annotations["code"])

    # Handle links
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

  # Resolve a page mention to an entity reference
  defp resolve_page_mention(page_id, display_name, campaign_id) do
    # Normalize the page_id (Notion uses UUIDs without dashes sometimes)
    normalized_id = normalize_uuid(page_id)

    # Try to find the entity by notion_page_id
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
        # Entity not found - just use the display name with a generic link marker
        {"[[#{display_name}]]", %{}}
    end
  end

  # Helper to normalize UUID format
  defp normalize_uuid(uuid) when is_binary(uuid) do
    cond do
      String.contains?(uuid, "-") ->
        uuid

      String.length(uuid) == 32 ->
        # Insert dashes: 8-4-4-4-12
        <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
          e::binary-size(12)>> = uuid

        "#{a}-#{b}-#{c}-#{d}-#{e}"

      true ->
        uuid
    end
  end

  # Merge mentions maps
  defp merge_mentions(map1, map2) do
    Map.merge(map1, map2, fn _k, v1, v2 ->
      Enum.uniq(v1 ++ v2)
    end)
  end

  # Markdown formatting helpers
  defp maybe_apply_bold(text, true), do: "**#{text}**"
  defp maybe_apply_bold(text, _), do: text

  defp maybe_apply_italic(text, true), do: "_#{text}_"
  defp maybe_apply_italic(text, _), do: text

  defp maybe_apply_strikethrough(text, true), do: "~~#{text}~~"
  defp maybe_apply_strikethrough(text, _), do: text

  defp maybe_apply_code(text, true), do: "`#{text}`"
  defp maybe_apply_code(text, _), do: text

  # Convert Notion blocks to plain text
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

      # Skip image blocks - Notion uses temporary signed URLs that expire
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

  # =============================================================================
  # Site, Party, Faction, Juncture Sync Functions
  # =============================================================================
  # These use generic helpers to reduce code duplication

  @doc """
  Sync a site to Notion. Creates a new page if no notion_page_id exists,
  otherwise updates the existing page.
  """
  def sync_site(%Site{} = site) do
    # Ensure associations are loaded for as_notion, including campaign for database IDs
    site = Repo.preload(site, [:faction, :juncture, :campaign, attunements: :character])

    case get_database_id_for_entity(site.campaign, "sites") do
      {:error, :no_database_configured} ->
        {:error, :no_database_configured}

      {:ok, database_id} ->
        sync_entity(site, %{
          entity_type: "site",
          database_id: database_id,
          update_fn: &Sites.update_site/2,
          as_notion_fn: &Site.as_notion/1,
          token: get_token(site.campaign)
        })
    end
  end

  @doc """
  Sync a party to Notion. Creates a new page if no notion_page_id exists,
  otherwise updates the existing page.
  """
  def sync_party(%Party{} = party) do
    # Ensure associations are loaded for as_notion, including campaign for database IDs
    party = Repo.preload(party, [:faction, :juncture, :campaign, memberships: :character])

    case get_database_id_for_entity(party.campaign, "parties") do
      {:error, :no_database_configured} ->
        {:error, :no_database_configured}

      {:ok, database_id} ->
        sync_entity(party, %{
          entity_type: "party",
          database_id: database_id,
          update_fn: &Parties.update_party/2,
          as_notion_fn: &Party.as_notion/1,
          token: get_token(party.campaign)
        })
    end
  end

  @doc """
  Sync a faction to Notion. Creates a new page if no notion_page_id exists,
  otherwise updates the existing page.
  """
  def sync_faction(%Faction{} = faction) do
    # Ensure associations are loaded for as_notion, including campaign for database IDs
    faction = Repo.preload(faction, [:characters, :campaign])

    case get_database_id_for_entity(faction.campaign, "factions") do
      {:error, :no_database_configured} ->
        {:error, :no_database_configured}

      {:ok, database_id} ->
        sync_entity(faction, %{
          entity_type: "faction",
          database_id: database_id,
          update_fn: &Factions.update_faction/2,
          as_notion_fn: &Faction.as_notion/1,
          token: get_token(faction.campaign)
        })
    end
  end

  @doc """
  Sync a juncture to Notion. Creates a new page if no notion_page_id exists,
  otherwise updates the existing page.
  """
  def sync_juncture(%Juncture{} = juncture) do
    # Preload campaign for database IDs
    juncture = Repo.preload(juncture, :campaign)

    case get_database_id_for_entity(juncture.campaign, "junctures") do
      {:error, :no_database_configured} ->
        {:error, :no_database_configured}

      {:ok, database_id} ->
        sync_entity(juncture, %{
          entity_type: "juncture",
          database_id: database_id,
          update_fn: &Junctures.update_juncture/2,
          as_notion_fn: &juncture_as_notion/1,
          token: get_token(juncture.campaign)
        })
    end
  end

  @doc """
  Sync an adventure to Notion. Creates a new page if no notion_page_id exists,
  otherwise updates the existing page.
  """
  def sync_adventure(%Adventure{} = adventure) do
    # Ensure associations are loaded for as_notion, including campaign for database IDs
    adventure =
      Repo.preload(adventure, [
        :user,
        :campaign,
        adventure_characters: :character,
        adventure_villains: :character,
        adventure_fights: :fight
      ])

    case get_database_id_for_entity(adventure.campaign, "adventures") do
      {:error, :no_database_configured} ->
        {:error, :no_database_configured}

      {:ok, database_id} ->
        sync_entity(adventure, %{
          entity_type: "adventure",
          database_id: database_id,
          update_fn: &Adventures.update_adventure/2,
          as_notion_fn: &Adventure.as_notion/1,
          token: get_token(adventure.campaign)
        })
    end
  end

  @doc """
  Sync a site FROM Notion, overwriting local data with the Notion page data.
  """
  def update_site_from_notion(site, opts \\ [])

  def update_site_from_notion(%Site{notion_page_id: nil}, _opts), do: {:error, :no_page_id}

  def update_site_from_notion(%Site{} = site, opts) do
    payload = %{"page_id" => site.notion_page_id}
    client = notion_client(opts)

    case client.get_page(site.notion_page_id) do
      nil ->
        Logger.error("Failed to fetch Notion page: #{site.notion_page_id}")
        log_sync_error("site", site.id, payload, %{}, "Notion page not found")
        {:error, :notion_page_not_found}

      %{"code" => error_code, "message" => message} = response ->
        Logger.error("Notion API error: #{error_code} - #{message}")

        log_sync_error(
          "site",
          site.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      page when is_map(page) ->
        # Use mention-aware conversion with campaign_id
        attributes = entity_attributes_from_notion(page, site.campaign_id)

        # Fetch rich description from page content (blocks)
        attributes = add_rich_description(attributes, site.notion_page_id, site.campaign_id)

        # Skip Notion sync to prevent ping-pong loops when updating from webhook
        case Sites.update_site(site, attributes, skip_notion_sync: true) do
          {:ok, updated_site} = result ->
            Notion.log_success("site", updated_site.id, payload, page)
            result

          {:error, changeset} = error ->
            log_sync_error(
              "site",
              site.id,
              payload,
              page,
              "Failed to update site from Notion: #{inspect(changeset)}"
            )

            error
        end
    end
  rescue
    error ->
      Logger.error("Failed to update site from Notion: #{Exception.message(error)}")

      log_sync_error(
        "site",
        site.id,
        %{"page_id" => site.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  @doc """
  Sync a party FROM Notion, overwriting local data with the Notion page data.
  """
  def update_party_from_notion(party, opts \\ [])

  def update_party_from_notion(%Party{notion_page_id: nil}, _opts), do: {:error, :no_page_id}

  def update_party_from_notion(%Party{} = party, opts) do
    payload = %{"page_id" => party.notion_page_id}
    client = notion_client(opts)

    case client.get_page(party.notion_page_id) do
      nil ->
        Logger.error("Failed to fetch Notion page: #{party.notion_page_id}")
        log_sync_error("party", party.id, payload, %{}, "Notion page not found")
        {:error, :notion_page_not_found}

      %{"code" => error_code, "message" => message} = response ->
        Logger.error("Notion API error: #{error_code} - #{message}")

        log_sync_error(
          "party",
          party.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      page when is_map(page) ->
        # Use mention-aware conversion with campaign_id
        attributes = entity_attributes_from_notion(page, party.campaign_id)

        # Fetch rich description from page content (blocks)
        attributes = add_rich_description(attributes, party.notion_page_id, party.campaign_id)

        # Skip Notion sync to prevent ping-pong loops when updating from webhook
        case Parties.update_party(party, attributes, skip_notion_sync: true) do
          {:ok, updated_party} = result ->
            Notion.log_success("party", updated_party.id, payload, page)
            result

          {:error, changeset} = error ->
            log_sync_error(
              "party",
              party.id,
              payload,
              page,
              "Failed to update party from Notion: #{inspect(changeset)}"
            )

            error
        end
    end
  rescue
    error ->
      Logger.error("Failed to update party from Notion: #{Exception.message(error)}")

      log_sync_error(
        "party",
        party.id,
        %{"page_id" => party.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  @doc """
  Sync a faction FROM Notion, overwriting local data with the Notion page data.
  """
  def update_faction_from_notion(faction, opts \\ [])

  def update_faction_from_notion(%Faction{notion_page_id: nil}, _opts), do: {:error, :no_page_id}

  def update_faction_from_notion(%Faction{} = faction, opts) do
    payload = %{"page_id" => faction.notion_page_id}
    client = notion_client(opts)

    case client.get_page(faction.notion_page_id) do
      nil ->
        Logger.error("Failed to fetch Notion page: #{faction.notion_page_id}")
        log_sync_error("faction", faction.id, payload, %{}, "Notion page not found")
        {:error, :notion_page_not_found}

      %{"code" => error_code, "message" => message} = response ->
        Logger.error("Notion API error: #{error_code} - #{message}")

        log_sync_error(
          "faction",
          faction.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      page when is_map(page) ->
        # Use mention-aware conversion with campaign_id
        attributes = entity_attributes_from_notion(page, faction.campaign_id)

        # Fetch rich description from page content (blocks)
        attributes = add_rich_description(attributes, faction.notion_page_id, faction.campaign_id)

        # Skip Notion sync to prevent ping-pong loops when updating from webhook
        case Factions.update_faction(faction, attributes, skip_notion_sync: true) do
          {:ok, updated_faction} = result ->
            Notion.log_success("faction", updated_faction.id, payload, page)
            result

          {:error, changeset} = error ->
            log_sync_error(
              "faction",
              faction.id,
              payload,
              page,
              "Failed to update faction from Notion: #{inspect(changeset)}"
            )

            error
        end
    end
  rescue
    error ->
      Logger.error("Failed to update faction from Notion: #{Exception.message(error)}")

      log_sync_error(
        "faction",
        faction.id,
        %{"page_id" => faction.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  @doc """
  Sync a juncture FROM Notion, overwriting local data with the Notion page data.
  """
  def update_juncture_from_notion(juncture, opts \\ [])

  def update_juncture_from_notion(%Juncture{notion_page_id: nil}, _opts),
    do: {:error, :no_page_id}

  def update_juncture_from_notion(%Juncture{} = juncture, opts) do
    payload = %{"page_id" => juncture.notion_page_id}
    client = notion_client(opts)

    case client.get_page(juncture.notion_page_id) do
      nil ->
        Logger.error("Failed to fetch Notion page: #{juncture.notion_page_id}")
        log_sync_error("juncture", juncture.id, payload, %{}, "Notion page not found")
        {:error, :notion_page_not_found}

      %{"code" => error_code, "message" => message} = response ->
        Logger.error("Notion API error: #{error_code} - #{message}")

        log_sync_error(
          "juncture",
          juncture.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      page when is_map(page) ->
        # Use mention-aware conversion with campaign_id
        attributes = entity_attributes_from_notion(page, juncture.campaign_id)

        attributes =
          case character_ids_from_notion(page, juncture.campaign_id) do
            {:ok, character_ids} -> Map.put(attributes, :character_ids, character_ids)
            :skip -> attributes
          end

        attributes =
          case site_ids_from_notion(page, juncture.campaign_id) do
            {:ok, site_ids} -> Map.put(attributes, :site_ids, site_ids)
            :skip -> attributes
          end

        # Fetch rich description from page content (blocks)
        attributes =
          add_rich_description(attributes, juncture.notion_page_id, juncture.campaign_id)

        case Junctures.update_juncture(juncture, attributes) do
          {:ok, updated_juncture} = result ->
            Notion.log_success("juncture", updated_juncture.id, payload, page)
            result

          {:error, changeset} = error ->
            log_sync_error(
              "juncture",
              juncture.id,
              payload,
              page,
              "Failed to update juncture from Notion: #{inspect(changeset)}"
            )

            error
        end
    end
  rescue
    error ->
      Logger.error("Failed to update juncture from Notion: #{Exception.message(error)}")

      log_sync_error(
        "juncture",
        juncture.id,
        %{"page_id" => juncture.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  @doc """
  Sync an adventure FROM Notion, overwriting local data with the Notion page data.
  """
  def update_adventure_from_notion(adventure, opts \\ [])

  def update_adventure_from_notion(%Adventure{notion_page_id: nil}, _opts),
    do: {:error, :no_page_id}

  def update_adventure_from_notion(%Adventure{} = adventure, opts) do
    payload = %{"page_id" => adventure.notion_page_id}
    client = notion_client(opts)

    case client.get_page(adventure.notion_page_id) do
      nil ->
        Logger.error("Failed to fetch Notion page: #{adventure.notion_page_id}")
        log_sync_error("adventure", adventure.id, payload, %{}, "Notion page not found")
        {:error, :notion_page_not_found}

      %{"code" => error_code, "message" => message} = response ->
        Logger.error("Notion API error: #{error_code} - #{message}")

        log_sync_error(
          "adventure",
          adventure.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      page when is_map(page) ->
        # Use centralized mention-aware conversion with campaign_id
        attributes = adventure_attributes_from_notion(page, adventure.campaign_id)

        # Fetch rich description from page content (blocks)
        attributes =
          add_rich_description(attributes, adventure.notion_page_id, adventure.campaign_id)

        # Skip Notion sync to prevent ping-pong loops when updating from webhook
        case Adventures.update_adventure(adventure, attributes, skip_notion_sync: true) do
          {:ok, updated_adventure} = result ->
            Notion.log_success("adventure", updated_adventure.id, payload, page)
            result

          {:error, changeset} = error ->
            log_sync_error(
              "adventure",
              adventure.id,
              payload,
              page,
              "Failed to update adventure from Notion: #{inspect(changeset)}"
            )

            error
        end
    end
  rescue
    error ->
      Logger.error("Failed to update adventure from Notion: #{Exception.message(error)}")

      log_sync_error(
        "adventure",
        adventure.id,
        %{"page_id" => adventure.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  # =============================================================================
  # Generic Entity Sync Helpers
  # =============================================================================

  # Generic sync function for any entity type (site, party, faction, juncture)
  defp sync_entity(entity, %{entity_type: entity_type} = opts) do
    case Map.get(opts, :token) do
      nil ->
        Logger.warning("Notion sync skipped for #{entity_type}: missing OAuth token")
        Notion.log_error(entity_type, entity.id, %{}, %{}, "Notion OAuth token missing")
        {:error, :no_notion_oauth_token}

      token ->
        try do
          opts = Map.put(opts, :token, token)

          result =
            if entity.notion_page_id do
              update_notion_page(entity, opts)
            else
              create_notion_page(entity, opts)
            end

          case result do
            {:ok, :unlinked} ->
              {:ok, :unlinked}

            {:ok, _} ->
              opts.update_fn.(entity, %{last_synced_to_notion_at: DateTime.utc_now()})

            {:error, reason} ->
              Logger.error("Failed to sync #{entity_type} to Notion: #{inspect(reason)}")
              {:error, reason}
          end
        rescue
          error ->
            Logger.error(
              "Exception syncing #{entity_type} to Notion: #{Exception.message(error)}"
            )

            {:error, error}
        end
    end
  end

  # Generic create function for any entity type
  defp create_notion_page(entity, %{entity_type: entity_type} = opts) do
    properties = opts.as_notion_fn.(entity)
    token = Map.get(opts, :token)

    case data_source_id_for(opts.database_id, token: token) do
      {:ok, data_source_id} ->
        payload = %{
          "parent" => %{"data_source_id" => data_source_id},
          "properties" => properties,
          :token => token
        }

        page = NotionClient.create_page(payload)

        case page do
          %{"id" => page_id} when is_binary(page_id) ->
            Notion.log_success(entity_type, entity.id, payload, page)

            case opts.update_fn.(entity, %{notion_page_id: page_id}) do
              {:ok, updated_entity} ->
                Logger.info(
                  "Created Notion page for #{entity_type} #{updated_entity.id}: #{page_id}"
                )

                # Add image if present
                add_image_to_notion(updated_entity)

                {:ok, page}

              {:error, changeset} ->
                Logger.error("Failed to update #{entity_type} with notion_page_id")
                {:error, changeset}
            end

          %{"code" => error_code, "message" => message} ->
            Logger.error("Notion API error creating #{entity_type}: #{error_code} - #{message}")

            Notion.log_error(
              entity_type,
              entity.id,
              payload,
              page,
              "Notion API error: #{error_code} - #{message}"
            )

            {:error, {:notion_api_error, error_code, message}}

          _ ->
            Logger.error("Unexpected response from Notion API when creating #{entity_type}")

            Notion.log_error(
              entity_type,
              entity.id,
              payload,
              page,
              "Unexpected response from Notion API"
            )

            {:error, :unexpected_notion_response}
        end

      {:error, reason} ->
        Logger.error(
          "Failed to resolve Notion data source for #{entity_type}: #{inspect(reason)}"
        )

        Notion.log_error(
          entity_type,
          entity.id,
          %{},
          %{},
          "Notion data source lookup failed: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Failed to create Notion page for #{entity_type}: #{Exception.message(error)}")

      Notion.log_error(
        entity_type,
        entity.id,
        %{},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, :notion_request_failed}
  end

  # Generic update function for any entity type
  defp update_notion_page(%{notion_page_id: nil}, _opts), do: {:error, :no_page_id}

  defp update_notion_page(entity, %{entity_type: entity_type} = opts) do
    properties = opts.as_notion_fn.(entity)
    token = Map.get(opts, :token)
    payload = %{"page_id" => entity.notion_page_id, "properties" => properties}
    response = NotionClient.update_page(entity.notion_page_id, properties, %{token: token})

    case response do
      %{"code" => "validation_error", "message" => message}
      when is_binary(message) ->
        if String.contains?(String.downcase(message), "archived") do
          handle_archived_entity(entity, opts, payload, response, message)
        else
          Logger.error("Notion API validation error on #{entity_type} update: #{message}")

          Notion.log_error(
            entity_type,
            entity.id,
            payload,
            response,
            "Notion API error: validation_error - #{message}"
          )

          {:error, {:notion_api_error, "validation_error", message}}
        end

      %{"code" => "object_not_found", "message" => _message} ->
        handle_archived_entity(entity, opts, payload, response, "object_not_found")

      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion API error on #{entity_type} update: #{error_code}")

        Notion.log_error(
          entity_type,
          entity.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      _ ->
        # Add image if not present in Notion
        page = NotionClient.get_page(entity.notion_page_id, %{token: token})

        image =
          case page do
            %{"code" => error_code, "message" => message} ->
              Logger.error(
                "Notion API error retrieving page #{entity.notion_page_id} " <>
                  "for #{entity_type} update: #{error_code} - #{message}"
              )

              nil

            nil ->
              Logger.error(
                "Notion API returned nil page for #{entity.notion_page_id} " <>
                  "on #{entity_type} update"
              )

              nil

            _ ->
              find_image_block(page)
          end

        unless image do
          add_image_to_notion(entity)
        end

        Notion.log_success(entity_type, entity.id, payload, response)
        {:ok, response}
    end
  rescue
    error ->
      Logger.error("Failed to update Notion page for #{entity_type}: #{Exception.message(error)}")

      Notion.log_error(
        entity_type,
        entity.id,
        %{"page_id" => entity.notion_page_id},
        %{},
        "Exception: #{Exception.message(error)}"
      )

      {:error, error}
  end

  # Generic handler for archived/deleted Notion pages
  defp handle_archived_entity(entity, opts, payload, response, message) do
    entity_type = opts.entity_type

    Logger.warning(
      "Notion page #{entity.notion_page_id} for #{entity_type} #{entity.id} " <>
        "has been archived/deleted. Unlinking from #{entity_type}."
    )

    Notion.log_error(
      entity_type,
      entity.id,
      payload,
      response,
      "Notion page archived/deleted - unlinking from #{entity_type}: #{message}"
    )

    case opts.update_fn.(entity, %{notion_page_id: nil}) do
      {:ok, _} ->
        Logger.info("Successfully unlinked Notion page from #{entity_type} #{entity.id}")
        {:ok, :unlinked}

      {:error, changeset} ->
        Logger.error("Failed to unlink Notion page from #{entity_type}: #{inspect(changeset)}")
        {:error, {:unlink_failed, changeset}}
    end
  end
end
