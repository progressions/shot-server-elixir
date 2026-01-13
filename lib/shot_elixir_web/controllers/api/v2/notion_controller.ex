defmodule ShotElixirWeb.Api.V2.NotionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Services.NotionService

  action_fallback ShotElixirWeb.FallbackController

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
