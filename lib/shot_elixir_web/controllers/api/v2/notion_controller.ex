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
  def characters(conn, params) do
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
end
