defmodule ShotElixir.Services.NotionService do
  @moduledoc """
  Business logic layer for Notion API integration.
  Handles character synchronization with Notion database.
  """

  require Logger

  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Notion
  alias ShotElixir.Repo

  import Ecto.Query

  # Use runtime config to allow token to be added at runtime without validation errors
  defp database_id do
    Application.get_env(:shot_elixir, :notion)[:database_id] ||
      "f6fa27ac-19cd-4b17-b218-55acc6d077be"
  end

  defp factions_database_id do
    Application.get_env(:shot_elixir, :notion)[:factions_database_id] ||
      "0ae94bfa1a754c8fbda28ea50afa5fd5"
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
  Create a new Notion page from character data.
  """
  def create_notion_from_character(%Character{} = character) do
    # Ensure faction is loaded for Notion properties
    character = Repo.preload(character, :faction)
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props = notion_faction_properties(character.faction.name)
        # Only add Faction if we found a matching faction in Notion
        if faction_props, do: Map.put(properties, "Faction", faction_props), else: properties
      else
        properties
      end

    Logger.debug("Creating Notion page with database_id: #{database_id()}")

    # Capture payload for logging
    payload = %{
      "parent" => %{"database_id" => database_id()},
      "properties" => properties
    }

    page = NotionClient.create_page(payload)

    Logger.debug("Notion API response received")

    # Check if Notion returned an error response
    case page do
      %{"id" => page_id} when is_binary(page_id) ->
        Logger.debug("Extracted page ID: #{inspect(page_id)}")

        # Log successful sync
        Notion.log_success(character.id, payload, page)

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
          character.id,
          payload,
          page,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      _ ->
        Logger.error("Unexpected response from Notion API")
        # Log error sync
        Notion.log_error(character.id, payload, page, "Unexpected response from Notion API")
        {:error, :unexpected_notion_response}
    end
  rescue
    error ->
      # Avoid logging potentially sensitive HTTP request metadata
      Logger.error("Failed to create Notion page: #{Exception.message(error)}")
      # Log error sync (with nil payload since we may not have gotten there)
      Notion.log_error(character.id, %{}, %{}, "Exception: #{Exception.message(error)}")
      {:error, :notion_request_failed}
  end

  @doc """
  Update existing Notion page with character data.
  """
  def update_notion_from_character(%Character{notion_page_id: nil}), do: {:error, :no_page_id}

  def update_notion_from_character(%Character{} = character) do
    properties = Character.as_notion(character)

    properties =
      if character.faction do
        faction_props = notion_faction_properties(character.faction.name)
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

    response = NotionClient.update_page(character.notion_page_id, properties)

    # Check if Notion returned an error response
    case response do
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion API error on update: #{error_code}")

        Notion.log_error(
          character.id,
          payload,
          response,
          "Notion API error: #{error_code} - #{message}"
        )

        {:error, {:notion_api_error, error_code, message}}

      _ ->
        # Add image if not present in Notion
        page = NotionClient.get_page(character.notion_page_id)
        image = find_image_block(page)

        unless image do
          add_image_to_notion(character)
        end

        # Log successful sync
        Notion.log_success(character.id, payload, response || page)

        {:ok, page}
    end
  rescue
    error ->
      Logger.error("Failed to update Notion page: #{Exception.message(error)}")
      # Log error sync
      Notion.log_error(
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
  def create_character_from_notion(page, campaign_id) do
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
    {:ok, character} = set_faction_from_notion(character, page, campaign_id)

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
  defp set_faction_from_notion(character, page, campaign_id) do
    case get_faction_name_from_notion(page) do
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
  defp get_faction_name_from_notion(page) do
    case get_in(page, ["properties", "Faction", "relation"]) do
      [%{"id" => faction_page_id} | _] ->
        faction_page = NotionClient.get_page(faction_page_id)

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
  def update_character_from_notion(%Character{notion_page_id: nil}), do: {:error, :no_page_id}

  def update_character_from_notion(%Character{} = character) do
    case NotionClient.get_page(character.notion_page_id) do
      # Defensive check: Req.get! typically raises on failure, but we handle
      # the unlikely case of a nil body for robustness
      nil ->
        Logger.error("Failed to fetch Notion page: #{character.notion_page_id}")
        {:error, :notion_page_not_found}

      # Handle Notion API error responses (e.g., page not found, unauthorized)
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion API error: #{error_code} - #{message}")
        {:error, {:notion_api_error, error_code, message}}

      # Success case: page data returned as a map
      page when is_map(page) ->
        attributes = Character.attributes_from_notion(character, page)

        # Add image if not already present
        add_image(page, character)

        Characters.update_character(character, attributes)
    end
  rescue
    error ->
      Logger.error("Failed to update character from Notion: #{Exception.message(error)}")
      {:error, error}
  end

  @doc """
  Search for Notion pages by name in the characters database.

  ## Parameters
    * `name` - The name to search for

  ## Returns
    * List of matching Notion pages from the characters database
  """
  def find_page_by_name(name) do
    filter = %{
      "property" => "Name",
      "title" => %{"contains" => name}
    }

    response = NotionClient.database_query(database_id(), %{"filter" => filter})
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

    response = NotionClient.database_query(factions_database_id(), %{"filter" => filter})
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
  def add_image(page, %Character{} = character) do
    # Check if character already has an image via ActiveStorage
    existing_image_url = ShotElixir.ActiveStorage.get_image_url("Character", character.id)

    if existing_image_url do
      {:ok, :skipped_existing_image}
    else
      case find_image_block(page) do
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

  # Session Notes Functions

  # Extracts the title from a Notion page's properties.
  # Tries both "title" and "Name" property keys since Notion pages can use either.
  defp extract_page_title(page) do
    get_in(page, ["properties", "title", "title", Access.at(0), "plain_text"]) ||
      get_in(page, ["properties", "Name", "title", Access.at(0), "plain_text"]) ||
      "Untitled"
  end

  @doc """
  Search for session notes pages in Notion.

  ## Parameters
    * `query` - Search query (e.g., "session 5-10" or "5-10")

  ## Returns
    * `{:ok, %{pages: [...], content: "..."}}` with matching pages and content of first match
    * `{:error, :not_found}` if no pages match
  """
  def fetch_session_notes(query) do
    search_query = if String.contains?(query, "session"), do: query, else: "session #{query}"

    results =
      NotionClient.search(search_query, %{
        "filter" => %{"property" => "object", "value" => "page"}
      })

    case results["results"] do
      [page | _rest] = pages ->
        # Fetch content of the first (most relevant) match
        blocks = NotionClient.get_block_children(page["id"])
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
        "Failed to fetch session notes for query=#{inspect(query)} " <>
          "search_query=#{inspect(search_query)}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      {:error, error}
  end

  @doc """
  Fetch a specific session page by ID.
  """
  def fetch_session_by_id(page_id) do
    page = NotionClient.get_page(page_id)

    case page do
      %{"id" => _id} ->
        blocks = NotionClient.get_block_children(page_id)
        content = parse_blocks_to_text(blocks["results"] || [])
        {:ok, %{title: extract_page_title(page), page_id: page_id, content: content}}

      %{"code" => error_code, "message" => message} ->
        {:error, {:notion_api_error, error_code, message}}

      _ ->
        {:error, :not_found}
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
    text = extract_rich_text(block["heading_1"]["rich_text"])
    "# #{text}\n"
  end

  defp parse_block(%{"type" => "heading_2"} = block) do
    text = extract_rich_text(block["heading_2"]["rich_text"])
    "## #{text}\n"
  end

  defp parse_block(%{"type" => "heading_3"} = block) do
    text = extract_rich_text(block["heading_3"]["rich_text"])
    "### #{text}\n"
  end

  defp parse_block(%{"type" => "paragraph"} = block) do
    text = extract_rich_text(block["paragraph"]["rich_text"])
    if text == "", do: nil, else: "#{text}\n"
  end

  defp parse_block(%{"type" => "bulleted_list_item"} = block) do
    text = extract_rich_text(block["bulleted_list_item"]["rich_text"])
    "- #{text}"
  end

  defp parse_block(%{"type" => "numbered_list_item"} = block) do
    text = extract_rich_text(block["numbered_list_item"]["rich_text"])
    # Intentionally always use "1." to leverage Markdown auto-numbering.
    # This keeps list numbering correct even if items are inserted or removed.
    "1. #{text}"
  end

  defp parse_block(%{"type" => "to_do"} = block) do
    text = extract_rich_text(block["to_do"]["rich_text"])
    checked = if block["to_do"]["checked"], do: "x", else: " "
    "- [#{checked}] #{text}"
  end

  defp parse_block(%{"type" => "toggle"} = block) do
    text = extract_rich_text(block["toggle"]["rich_text"])
    "▸ #{text}"
  end

  defp parse_block(%{"type" => "quote"} = block) do
    text = extract_rich_text(block["quote"]["rich_text"])
    "> #{text}"
  end

  defp parse_block(%{"type" => "callout"} = block) do
    text = extract_rich_text(block["callout"]["rich_text"])
    icon = get_in(block, ["callout", "icon", "emoji"]) || "💡"
    "> #{icon} #{text}"
  end

  defp parse_block(%{"type" => "code"} = block) do
    text = extract_rich_text(block["code"]["rich_text"])
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
    caption = extract_rich_text(block["bookmark"]["caption"] || [])
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

  defp extract_rich_text(nil), do: ""

  defp extract_rich_text(rich_text) when is_list(rich_text) do
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

  defp extract_rich_text(_), do: ""
end
