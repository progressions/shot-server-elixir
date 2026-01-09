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
    name = params["name"] || ""

    case NotionService.find_page_by_name(name) do
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

      {:error, {:notion_api_error, code, message}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Notion API error", code: code, message: message})

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
end
