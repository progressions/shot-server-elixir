defmodule ShotElixirWeb.Api.V2.SearchController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Search

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  Search across all entity types within the current campaign.

  GET /api/v2/search?q=term

  Returns results grouped by entity type, max 5 per type.
  """
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            query = (params["q"] || "") |> String.trim()

            result = Search.search_campaign(campaign.id, query)

            conn
            |> put_view(ShotElixirWeb.Api.V2.SearchView)
            |> render("index.json", result)
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
      Campaigns.is_member?(campaign.id, user.id)
  end
end
