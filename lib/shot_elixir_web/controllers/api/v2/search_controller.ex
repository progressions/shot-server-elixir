defmodule ShotElixirWeb.Api.V2.SearchController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Guardian
  alias ShotElixir.Search

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  Search across all entity types within the current campaign.

  GET /api/v2/search?q=term

  Returns results grouped by entity type, max 5 per type.
  """
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      query = params["q"] |> to_string() |> String.trim()

      if query == "" do
        conn
        |> put_view(ShotElixirWeb.Api.V2.SearchView)
        |> render("index.json", results: %{})
      else
        results = Search.search_all(campaign_id, query)

        conn
        |> put_view(ShotElixirWeb.Api.V2.SearchView)
        |> render("index.json", results: results)
      end
    end
  end
end
