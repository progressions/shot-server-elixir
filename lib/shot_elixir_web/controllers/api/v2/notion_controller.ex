defmodule ShotElixirWeb.Api.V2.NotionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Services.NotionService
  alias ShotElixir.Services.NotionClient

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  List databases available in the campaign's connected Notion workspace.
  Uses the authenticated user's current_campaign_id and the campaign's OAuth access token.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Response
    * 200 - List of databases with id and title
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found or Notion not connected
    * 500 - Internal server error if Notion API fails
  """
  def databases(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:current_campaign, campaign_id} when not is_nil(campaign_id) <-
           {:current_campaign, user.current_campaign_id},
         {:campaign, %Campaigns.Campaign{} = campaign} <-
           {:campaign, Campaigns.get_campaign(campaign_id)},
         {:token, token} when not is_nil(token) <-
           {:token, campaign.notion_access_token} do
      # Use Notion search API to find all databases the user has access to
      # Wrapped in try-rescue since NotionClient.search uses Req.post! which can raise
      try do
        # Notion API 2025-09-03 uses "data_source" filter for databases
        case NotionClient.search("", %{
               token: token,
               filter: %{value: "data_source", property: "object"}
             }) do
          %{"results" => results} ->
            databases =
              results
              |> Enum.map(fn db ->
                %{
                  id: db["id"],
                  title: extract_database_title(db)
                }
              end)
              |> Enum.reject(fn db ->
                is_nil(db.title) || db.title == "Untitled"
              end)

            json(conn, databases)

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to fetch databases", details: inspect(reason)})

          other ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Unexpected response from Notion", details: inspect(other)})
        end
      rescue
        error ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to connect to Notion", details: inspect(error)})
      end
    else
      {:current_campaign, nil} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No current campaign set"})

      {:campaign, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found"})

      {:token, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Notion not connected for this campaign"})
    end
  end

  # Extract database title from Notion database object
  # Uses Map.get/3 for nil safety in case of malformed Notion API responses
  defp extract_database_title(%{"title" => title}) when is_list(title) do
    title
    |> Enum.map(fn t -> Map.get(t || %{}, "plain_text", "") end)
    |> Enum.join("")
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp extract_database_title(_), do: nil

  @doc """
  Search for characters in the campaign's Notion Characters database.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching character pages (JSON array)
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found, Notion not connected, or characters database not configured
  """
  def search(conn, params) do
    search_campaign_notion_entities(conn, params, "characters")
  end

  @doc """
  Fetch session notes from Notion.

  ## Parameters
    * `q` - Search query for session (e.g., "5-10", "session 5-10")
    * `id` - Specific page ID to fetch (alternative to search)

  ## Response
    * 200 - Session content with title, page_id, content, and matching pages
    * 404 - No session found matching query
    * 500 - Internal server error if Notion API fails
  """
  def sessions(conn, %{"id" => page_id}) when is_binary(page_id) and page_id != "" do
    case NotionService.fetch_session_by_id(page_id) do
      {:ok, session} ->
        json(conn, session)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, {:notion_api_error, code, message}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Notion API error", code: code, message: message})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch session"})
    end
  end

  # Parameter 'q' is used for search queries following common API conventions (e.g., GitHub, Google).
  # Parameter 'id' is used for direct page ID lookup, providing explicit intent.
  def sessions(conn, %{"q" => query}) when is_binary(query) and query != "" do
    case NotionService.fetch_session_notes(query) do
      {:ok, session} ->
        json(conn, session)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No session found matching '#{query}'"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch session notes"})
    end
  end

  def sessions(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: 'q' (search query) or 'id' (page ID)"})
  end

  @doc """
  Search for adventures in the campaign's Notion Adventures database.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching adventure pages (JSON array)
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found, Notion not connected, or adventures database not configured
  """
  def adventures(conn, params) do
    search_campaign_notion_entities(conn, params, "adventures")
  end

  @doc """
  Search for sites in the campaign's Notion Sites database.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching site pages (JSON array)
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found, Notion not connected, or sites database not configured
  """
  def search_sites(conn, params) do
    search_campaign_notion_entities(conn, params, "sites")
  end

  @doc """
  Search for parties in the campaign's Notion Parties database.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching party pages (JSON array)
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found, Notion not connected, or parties database not configured
  """
  def search_parties(conn, params) do
    search_campaign_notion_entities(conn, params, "parties")
  end

  @doc """
  Search for factions in the campaign's Notion Factions database.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching faction pages (JSON array)
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found, Notion not connected, or factions database not configured
  """
  def search_factions(conn, params) do
    search_campaign_notion_entities(conn, params, "factions")
  end

  @doc """
  Search for junctures in the campaign's Notion Junctures database.

  ## Authentication
  Requires JWT authentication. Uses the authenticated user's `current_campaign_id`.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching juncture pages (JSON array)
    * 400 - No current campaign set for the authenticated user
    * 404 - Campaign not found, Notion not connected, or junctures database not configured
  """
  def search_junctures(conn, params) do
    search_campaign_notion_entities(conn, params, "junctures")
  end

  # Private helper to search Notion entities using campaign's OAuth token and database mapping.
  # Uses the current user's current_campaign_id instead of requiring campaign_id parameter.
  defp search_campaign_notion_entities(conn, params, entity_type) do
    user = Guardian.Plug.current_resource(conn)
    name = params["name"] || ""

    with {:current_campaign, campaign_id} when not is_nil(campaign_id) <-
           {:current_campaign, user.current_campaign_id},
         {:campaign, %Campaigns.Campaign{} = campaign} <-
           {:campaign, Campaigns.get_campaign(campaign_id)},
         {:token, token} when not is_nil(token) <-
           {:token, campaign.notion_access_token},
         {:database, database_id} when not is_nil(database_id) and database_id != "" <-
           {:database, get_in(campaign.notion_database_ids || %{}, [entity_type])} do
      case NotionService.find_pages_in_database(database_id, name, token: token) do
        pages when is_list(pages) ->
          json(conn, pages)

        {:error, reason} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to search #{entity_type}", details: inspect(reason)})
      end
    else
      {:current_campaign, nil} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No current campaign set"})

      {:campaign, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found or Notion not connected"})

      {:token, nil} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Notion not connected for this campaign"})

      {:database, _} ->
        # No database mapped for this entity type
        conn
        |> put_status(:not_found)
        |> json(%{error: "No #{entity_type} database configured for this campaign"})
    end
  rescue
    error ->
      conn
      |> put_status(:internal_server_error)
      |> json(%{error: "Failed to search Notion", details: inspect(error)})
  end
end
