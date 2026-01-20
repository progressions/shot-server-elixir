defmodule ShotElixir.Services.NotionService do
  @moduledoc """
  Business logic layer for Notion API integration.
  Handles synchronization of characters, sites, parties, factions, and junctures with Notion databases.
  """

  require Logger

  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Services.Notion.{Blocks, Config, Images, Mappers, Search}
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

  import Ecto.Query

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

  # Delegate configuration helpers to dedicated module
  defdelegate get_token(campaign_or_id), to: Config
  defdelegate get_database_id_for_entity(campaign, entity_type), to: Config
  defdelegate init_data_source_cache(), to: Config
  defdelegate get_bot_user_id(opts), to: Config
  defdelegate find_page_by_name(name), to: Search
  defdelegate find_pages_in_database(data_source_id, name, opts \\ []), to: Search
  defdelegate find_faction_by_name(campaign, name, opts \\ []), to: Search
  defdelegate find_image_block(page, opts \\ []), to: Images
  defdelegate add_image_to_notion(entity), to: Images
  defdelegate add_image(page, character), to: Images
  defdelegate fetch_session_notes(query, token), to: Blocks
  defdelegate fetch_session_by_id(page_id, token), to: Blocks
  defdelegate parse_blocks_to_text(blocks), to: Blocks
  defdelegate fetch_adventure(query), to: Blocks
  defdelegate fetch_adventure_by_id(page_id), to: Blocks
  defdelegate fetch_page_content(page_id), to: Blocks
  defdelegate fetch_rich_description(page_id, campaign_id, token), to: Blocks
  defdelegate get_description(page), to: Mappers
  defdelegate get_raw_action_values_from_notion(page), to: Mappers
  defdelegate get_notion_name(page), to: Mappers
  defdelegate get_rich_text_as_html(props, key, campaign_id), to: Mappers
  defdelegate entity_attributes_from_notion(page, campaign_id), to: Mappers
  defdelegate adventure_attributes_from_notion(page, campaign_id), to: Mappers
  defdelegate add_rich_description(attrs, page_id, campaign_id, token), to: Mappers
  defdelegate juncture_as_notion(juncture), to: Mappers
  defdelegate character_ids_from_notion(page, campaign_id), to: Mappers
  defdelegate site_ids_from_notion(page, campaign_id), to: Mappers
  defdelegate hero_ids_from_notion(page, campaign_id), to: Mappers
  defdelegate villain_ids_from_notion(page, campaign_id), to: Mappers
  defdelegate member_ids_from_notion(page, campaign_id), to: Mappers
  defdelegate data_source_id_for(database_id, opts \\ []), to: Config
  defdelegate skip_bot_update?(page, opts \\ []), to: Config

  defp notion_client(opts), do: Config.client(opts)

  defp log_sync_error(entity_type, entity_id, payload, response, message) do
    Notion.log_error(entity_type, entity_id, payload, response, message)
  end

  defp notion_faction_properties(campaign, name) do
    case find_faction_by_name(campaign, name) do
      [faction | _] -> %{"relation" => [%{"id" => faction["id"]}]}
      _ -> nil
    end
  end

  @doc """
  Main sync function - creates or updates character in Notion.
  Environment check performed at worker level.
  """
  def sync_character(%Character{} = character) do
    character = Repo.preload(character, [:faction, :juncture])

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
    character = Repo.preload(character, [:faction, :juncture, :campaign])
    token = get_token(character.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Fetch the Notion page
      case NotionClient.get_page(notion_page_id, token: token) do
        %{"code" => error_code, "message" => message} ->
          Logger.error("Notion API error: #{error_code} - #{message}")
          {:error, {:notion_api_error, error_code, message}}

        nil ->
          {:error, :notion_page_not_found}

        page when is_map(page) ->
          # Extract RAW values from Notion (not using attributes_from_notion which applies av_or_new)
          # This ensures we're merging with the actual Notion values, not pre-processed ones
          raw_notion_action_values = get_raw_action_values_from_notion(page)
          notion_description = get_description(page)
          notion_name = get_notion_name(page)
          notion_at_a_glance = get_in(page, ["properties", "At a Glance", "checkbox"])

          # Perform smart merge for action_values
          merged_action_values =
            smart_merge_action_values(
              character.action_values || Character.default_action_values(),
              raw_notion_action_values
            )

          # Perform smart merge for description
          merged_description =
            smart_merge_description(
              character.description || %{},
              notion_description
            )

          # Merge name (Notion wins only if Chi War is blank)
          merged_name =
            if blank?(character.name),
              do: notion_name || character.name,
              else: character.name

          # Update Chi War record with merged values
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
              # Now sync the merged data back to Notion
              updated_character = Repo.preload(updated_character, [:faction, :juncture])

              # Log warning if Notion update fails (but don't fail the merge)
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

              # Set faction from Notion if not already set
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

              # Set juncture from Notion if not already set
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

              # Add image from Notion if character doesn't have one
              add_image(page, updated_character)

              # Log successful merge
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
    # Ensure faction, juncture, and campaign are loaded for Notion properties and database ID
    character = Repo.preload(character, [:faction, :juncture, :campaign])
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props = notion_faction_properties(character.campaign, character.faction.name)
        # Only add Faction if we found a matching faction in Notion
        if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
      else
        properties
      end

    token = get_token(character.campaign)

    with {:ok, database_id} <- get_database_id_for_entity(character.campaign, "characters"),
         {:ok, data_source_id} <- data_source_id_for(database_id, token: token) do
      Logger.debug("Creating Notion page with data_source_id: #{data_source_id}")

      # Separate payload for logging (without token) and API call (with token)
      log_payload = %{
        "parent" => %{"data_source_id" => data_source_id},
        "properties" => properties
      }

      api_payload = Map.put(log_payload, :token, token)
      page = NotionClient.create_page(api_payload)

      Logger.debug("Notion API response received")

      # Check if Notion returned an error response
      case page do
        %{"id" => page_id} when is_binary(page_id) ->
          Logger.debug("Extracted page ID: #{inspect(page_id)}")

          # Log successful sync
          Notion.log_success("character", character.id, log_payload, page)

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
            log_payload,
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
            log_payload,
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
    # Ensure campaign, faction, and juncture are loaded for relation properties
    character = Repo.preload(character, [:campaign, :faction, :juncture])
    token = get_token(character.campaign)
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
        image = find_image_block(page)

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

  @doc """
  Create a new character from Notion page data.
  Always creates a new character. If a character with the same name exists,
  generates a unique name (e.g., "Character Name (1)") to avoid conflicts.

  Also imports:
  - Faction (from Notion relation, matched by name to local faction)
  - Juncture (from Notion multi_select, matched by name to local juncture)
  - Fortune and other action values
  """
  def create_character_from_notion(page, campaign_id, token) do
    name = get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"])

    # Generate unique name to avoid overwriting existing characters
    # If "Hero" exists, this will return "Hero (1)"
    unique_name = Characters.generate_unique_name(name, campaign_id)

    # Always create a new character for imports from Notion
    {:ok, character} = Characters.create_character(%{name: unique_name, campaign_id: campaign_id})

    character = Repo.preload(character, [:faction, :juncture])
    attributes = Character.attributes_from_notion(character, page)
    attributes = add_rich_description(attributes, page["id"], campaign_id, token)

    {:ok, character} =
      Characters.update_character(character, Map.put(attributes, :notion_page_id, page["id"]))

    # Look up and set faction from Notion relation
    {:ok, character} = set_faction_from_notion(character, page, campaign_id, token)

    # Look up and set juncture from Notion multi_select
    {:ok, character} = set_juncture_from_notion(character, page, campaign_id)

    # Add image if not already present
    add_image(page, character)

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
        faction_page = NotionClient.get_page(faction_page_id, token: token)

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
    character = Repo.preload(character, :campaign)
    token = get_token(character.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Ensure token is in opts for skip_bot_update? check (only if not already provided)
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => character.notion_page_id}
      client = notion_client(opts)

      case client.get_page(character.notion_page_id, token: token) do
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
          if skip_bot_update?(page, opts) do
            Logger.info(
              "Skipping update for character #{character.id} as it was last edited by the bot"
            )

            {:ok, character}
          else
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
            add_image(page, character)

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
    # Preload campaign for database IDs and faction for relations
    juncture = Repo.preload(juncture, [:campaign, :faction])

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
    site = Repo.preload(site, :campaign)
    token = get_token(site.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Ensure token is in opts for skip_bot_update? check (only if not already provided)
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => site.notion_page_id}
      client = notion_client(opts)

      case client.get_page(site.notion_page_id, token: token) do
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
          if skip_bot_update?(page, opts) do
            Logger.info("Skipping update for site #{site.id} as it was last edited by the bot")

            {:ok, site}
          else
            # Use mention-aware conversion with campaign_id
            attributes = entity_attributes_from_notion(page, site.campaign_id)

            # Fetch rich description from page content (blocks)
            attributes =
              add_rich_description(attributes, site.notion_page_id, site.campaign_id, token)

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
    party = Repo.preload(party, :campaign)
    token = get_token(party.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Ensure token is in opts for skip_bot_update? check (only if not already provided)
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => party.notion_page_id}
      client = notion_client(opts)

      case client.get_page(party.notion_page_id, token: token) do
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
          if skip_bot_update?(page, opts) do
            Logger.info("Skipping update for party #{party.id} as it was last edited by the bot")

            {:ok, party}
          else
            # Use mention-aware conversion with campaign_id
            attributes = entity_attributes_from_notion(page, party.campaign_id)

            # Fetch rich description from page content (blocks)
            attributes =
              add_rich_description(attributes, party.notion_page_id, party.campaign_id, token)

            # Skip Notion sync to prevent ping-pong loops when updating from webhook
            case Parties.update_party(party, attributes, skip_notion_sync: true) do
              {:ok, updated_party} ->
                # Sync memberships from Notion character relations
                sync_party_memberships_from_notion(updated_party, page)
                Notion.log_success("party", updated_party.id, payload, page)
                {:ok, updated_party}

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

  # Sync party memberships from Notion character relations
  # Creates memberships for characters linked in Notion, removes memberships for characters not in Notion
  defp sync_party_memberships_from_notion(party, page) do
    case character_ids_from_notion(page, party.campaign_id) do
      {:ok, notion_character_ids} ->
        # Get current membership character IDs (characters only, ignore vehicle-only memberships)
        party = Repo.preload(party, :memberships)

        current_character_ids =
          party.memberships
          |> Enum.map(& &1.character_id)
          |> Enum.reject(&is_nil/1)

        # Characters to add (in Notion but not in Chi War)
        to_add = notion_character_ids -- current_character_ids

        # Characters to remove (in Chi War but not in Notion)
        to_remove = current_character_ids -- notion_character_ids

        # Add new memberships with error handling
        Enum.each(to_add, fn character_id ->
          case Parties.add_member(party.id, %{"character_id" => character_id}) do
            {:ok, _membership} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to add character #{character_id} to party #{party.id}: #{inspect(reason)}"
              )
          end
        end)

        # Remove old memberships with error handling
        memberships_to_delete =
          Enum.filter(party.memberships, fn m -> m.character_id in to_remove end)

        Enum.each(memberships_to_delete, fn membership ->
          case Parties.remove_member(membership.id) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to remove membership #{membership.id} from party #{party.id}: #{inspect(reason)}"
              )
          end
        end)

        :ok

      :skip ->
        # No character relation property found, don't modify memberships
        :ok
    end
  end

  # Sync faction members from Notion character relations
  # Updates character faction_id fields based on Notion Members relation
  defp sync_faction_members_from_notion(faction, page) do
    case member_ids_from_notion(page, faction.campaign_id) do
      {:ok, notion_character_ids} ->
        # Get current member character IDs
        faction = Repo.preload(faction, :characters)
        current_character_ids = Enum.map(faction.characters, & &1.id)

        # Characters to add (in Notion but not in Chi War)
        to_add = notion_character_ids -- current_character_ids

        # Characters to remove (in Chi War but not in Notion)
        to_remove = current_character_ids -- notion_character_ids

        # Batch fetch characters to add (avoid N+1 queries)
        characters_to_add =
          if Enum.any?(to_add) do
            import Ecto.Query
            Repo.all(from c in Character, where: c.id in ^to_add)
          else
            []
          end

        # Batch fetch characters to remove (avoid N+1 queries)
        characters_to_remove =
          if Enum.any?(to_remove) do
            import Ecto.Query
            Repo.all(from c in Character, where: c.id in ^to_remove)
          else
            []
          end

        # Add new members by setting their faction_id with error handling
        Enum.each(characters_to_add, fn character ->
          case Characters.update_character(character, %{faction_id: faction.id},
                 skip_notion_sync: true
               ) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to add character #{character.id} to faction #{faction.id}: #{inspect(reason)}"
              )
          end
        end)

        # Remove old members by clearing their faction_id with error handling
        Enum.each(characters_to_remove, fn character ->
          case Characters.update_character(character, %{faction_id: nil}, skip_notion_sync: true) do
            {:ok, _} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to remove character #{character.id} from faction #{faction.id}: #{inspect(reason)}"
              )
          end
        end)

        :ok

      :skip ->
        # No member relation property found, don't modify faction memberships
        :ok
    end
  end

  @doc """
  Sync a faction FROM Notion, overwriting local data with the Notion page data.
  """
  def update_faction_from_notion(faction, opts \\ [])

  def update_faction_from_notion(%Faction{notion_page_id: nil}, _opts), do: {:error, :no_page_id}

  def update_faction_from_notion(%Faction{} = faction, opts) do
    faction = Repo.preload(faction, :campaign)
    token = get_token(faction.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Ensure token is in opts for skip_bot_update? check (only if not already provided)
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => faction.notion_page_id}
      client = notion_client(opts)

      case client.get_page(faction.notion_page_id, token: token) do
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
          if skip_bot_update?(page, opts) do
            Logger.info(
              "Skipping update for faction #{faction.id} as it was last edited by the bot"
            )

            {:ok, faction}
          else
            # Use mention-aware conversion with campaign_id
            attributes = entity_attributes_from_notion(page, faction.campaign_id)

            # Fetch rich description from page content (blocks)
            attributes =
              add_rich_description(attributes, faction.notion_page_id, faction.campaign_id, token)

            # Skip Notion sync to prevent ping-pong loops when updating from webhook
            case Factions.update_faction(faction, attributes, skip_notion_sync: true) do
              {:ok, updated_faction} ->
                # Sync member relations from Notion
                sync_faction_members_from_notion(updated_faction, page)
                Notion.log_success("faction", updated_faction.id, payload, page)
                {:ok, updated_faction}

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
    juncture = Repo.preload(juncture, :campaign)
    token = get_token(juncture.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Ensure token is in opts for skip_bot_update? check (only if not already provided)
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => juncture.notion_page_id}
      client = notion_client(opts)

      case client.get_page(juncture.notion_page_id, token: token) do
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
          if skip_bot_update?(page, opts) do
            Logger.info(
              "Skipping update for juncture #{juncture.id} as it was last edited by the bot"
            )

            {:ok, juncture}
          else
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
              add_rich_description(
                attributes,
                juncture.notion_page_id,
                juncture.campaign_id,
                token
              )

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
    adventure = Repo.preload(adventure, :campaign)
    token = get_token(adventure.campaign)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      # Ensure token is in opts for skip_bot_update? check (only if not already provided)
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => adventure.notion_page_id}
      client = notion_client(opts)

      case client.get_page(adventure.notion_page_id, token: token) do
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
          if skip_bot_update?(page, opts) do
            Logger.info(
              "Skipping update for adventure #{adventure.id} as it was last edited by the bot"
            )

            {:ok, adventure}
          else
            # Use centralized mention-aware conversion with campaign_id
            # Convert all atom keys to strings for consistency with update_adventure
            attributes =
              adventure_attributes_from_notion(page, adventure.campaign_id)
              |> Enum.map(fn {k, v} -> {to_string(k), v} end)
              |> Map.new()

            # Extract hero character IDs from Notion "Heroes" relation
            attributes =
              case hero_ids_from_notion(page, adventure.campaign_id) do
                {:ok, character_ids} -> Map.put(attributes, "character_ids", character_ids)
                :skip -> attributes
              end

            # Extract villain character IDs from Notion "Villains" relation
            attributes =
              case villain_ids_from_notion(page, adventure.campaign_id) do
                {:ok, villain_ids} -> Map.put(attributes, "villain_ids", villain_ids)
                :skip -> attributes
              end

            # Fetch rich description from page content (blocks)
            # add_rich_description now uses string keys for consistency
            attributes =
              add_rich_description(
                attributes,
                adventure.notion_page_id,
                adventure.campaign_id,
                token
              )

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
      Logger.error("Exception syncing #{entity_type} to Notion: #{Exception.message(error)}")
      {:error, error}
  end

  # Generic create function for any entity type
  defp create_notion_page(entity, %{entity_type: entity_type} = opts) do
    properties = opts.as_notion_fn.(entity)
    token = Map.get(opts, :token)

    case data_source_id_for(opts.database_id, token: token) do
      {:ok, data_source_id} ->
        # Separate payload for logging (without token) and API call (with token)
        log_payload = %{
          "parent" => %{"data_source_id" => data_source_id},
          "properties" => properties
        }

        api_payload = Map.put(log_payload, :token, token)
        page = NotionClient.create_page(api_payload)

        case page do
          %{"id" => page_id} when is_binary(page_id) ->
            Notion.log_success(entity_type, entity.id, log_payload, page)

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
              log_payload,
              page,
              "Notion API error: #{error_code} - #{message}"
            )

            {:error, {:notion_api_error, error_code, message}}

          _ ->
            Logger.error("Unexpected response from Notion API when creating #{entity_type}")

            Notion.log_error(
              entity_type,
              entity.id,
              log_payload,
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
