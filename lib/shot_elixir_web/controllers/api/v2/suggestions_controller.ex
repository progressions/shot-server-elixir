defmodule ShotElixirWeb.Api.V2.SuggestionsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Suggestions

  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    query = params["query"] || ""

    if current_user.current_campaign_id do
      results = Suggestions.search(current_user.current_campaign_id, query)

      conn
      |> put_view(ShotElixirWeb.Api.V2.SuggestionsView)
      |> render("index.json", suggestions: results)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end
end
