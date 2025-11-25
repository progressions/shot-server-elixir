defmodule ShotElixirWeb.Api.V2.NotionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Services.NotionService

  @doc """
  Search for Notion pages by name.
  Returns a list of matching Notion pages.

  ## Parameters
    * `name` - The name to search for (query parameter)

  ## Response
    * 200 - List of matching pages (JSON array)
  """
  def characters(conn, params) do
    name = params["name"] || ""

    pages = NotionService.find_page_by_name(name)

    json(conn, pages || [])
  end
end
