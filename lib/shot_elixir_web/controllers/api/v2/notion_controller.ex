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
end
