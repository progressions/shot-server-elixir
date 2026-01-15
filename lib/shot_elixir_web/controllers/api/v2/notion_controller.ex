defmodule ShotElixirWeb.Api.V2.NotionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Services.NotionService
  alias ShotElixir.Services.NotionClient

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  List databases available in the campaign's connected Notion workspace.
  Uses the campaign's OAuth access token to search for databases.

  ## Parameters
    * `campaign_id` - The campaign ID (required)

  ## Response
    * 200 - List of databases with id and title
    * 400 - Missing campaign_id parameter
    * 404 - Campaign not found or Notion not connected
    * 500 - Internal server error if Notion API fails
  """
  def databases(conn, %{"campaign_id" => campaign_id}) do
    user = Guardian.Plug.current_resource(conn)

    with %Campaigns.Campaign{} = campaign <- Campaigns.get_campaign(campaign_id),
         true <- campaign.user_id == user.id || Campaigns.is_member?(campaign.id, user.id),
         token when not is_nil(token) <- campaign.notion_access_token do
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
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found or Notion not connected"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "You do not have access to this campaign"})
    end
  end

  def databases(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: campaign_id"})
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
  Search for Notion pages by name.
  Returns a list of matching Notion pages.

  ## Parameters
    * `name` - The name to search for (query parameter)

  ## Response
    * 200 - List of matching pages (JSON array)
    * 500 - Internal server error if Notion API fails
  """
  def search(conn, params) do
    search_notion_entities(conn, params, &NotionService.find_page_by_name/1)
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
  Search for adventure pages in Notion or fetch a specific page by ID.

  ## Parameters
    * `q` - Search query (optional)
    * `id` - Notion page ID to fetch directly (optional)

  One of `q` or `id` must be provided.

  ## Response
    * 200 - Adventure data with title, page_id, content, and pages list
    * 400 - Bad request if neither q nor id provided
    * 404 - Not found if no matching pages
  """
  def adventures(conn, %{"id" => page_id}) when is_binary(page_id) and page_id != "" do
    case NotionService.fetch_adventure_by_id(page_id) do
      {:ok, adventure} ->
        json(conn, adventure)

      {:error, {:notion_api_error, "object_not_found", _message}} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Adventure not found"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch adventure", details: inspect(reason)})
    end
  end

  def adventures(conn, %{"q" => query}) when is_binary(query) and query != "" do
    case NotionService.fetch_adventure(query) do
      {:ok, %{pages: [], title: nil}} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No adventure found matching '#{query}'"})

      {:ok, adventure} ->
        json(conn, adventure)

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to search adventures", details: inspect(reason)})
    end
  end

  def adventures(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Must provide either 'q' (search query) or 'id' (page ID) parameter"})
  end

  @doc """
  Search for sites in the Notion Sites database.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching site pages (JSON array)
    * 500 - Internal server error if Notion API fails
  """
  def search_sites(conn, params) do
    search_notion_entities(conn, params, &NotionService.find_sites_in_notion/1)
  end

  @doc """
  Search for parties in the Notion Parties database.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching party pages (JSON array)
    * 500 - Internal server error if Notion API fails
  """
  def search_parties(conn, params) do
    search_notion_entities(conn, params, &NotionService.find_parties_in_notion/1)
  end

  @doc """
  Search for factions in the Notion Factions database.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching faction pages (JSON array)
    * 500 - Internal server error if Notion API fails
  """
  def search_factions(conn, params) do
    search_notion_entities(conn, params, &NotionService.find_factions_in_notion/1)
  end

  @doc """
  Search for junctures in the Notion Junctures database.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching juncture pages (JSON array)
    * 500 - Internal server error if Notion API fails
  """
  def search_junctures(conn, params) do
    search_notion_entities(conn, params, &NotionService.find_junctures_in_notion/1)
  end

  @doc """
  Search for adventures in the Notion Adventures database.

  ## Parameters
    * `name` - The name to search for (query parameter, optional)

  ## Response
    * 200 - List of matching adventure pages (JSON array)
    * 500 - Internal server error if Notion API fails
  """
  def search_adventures(conn, params) do
    search_notion_entities(conn, params, &NotionService.find_adventures_in_notion/1)
  end

  # Private helper to reduce duplication across Notion search endpoints.
  # Takes a service function and handles the common response patterns.
  defp search_notion_entities(conn, params, service_fn) do
    name = params["name"] || ""

    case service_fn.(name) do
      pages when is_list(pages) ->
        json(conn, pages)

      nil ->
        json(conn, [])

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end
end
