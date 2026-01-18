defmodule ShotElixirWeb.Api.V2.SearchController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
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

    with {:ok, campaign_id} <- get_current_campaign_id(current_user),
         campaign when not is_nil(campaign) <- Campaigns.get_campaign(campaign_id),
         :ok <- authorize_campaign_access(campaign, current_user) do
      query = (params["q"] || "") |> String.trim()
      result = Search.search_campaign(campaign.id, query)

      conn
      |> put_view(ShotElixirWeb.Api.V2.SearchView)
      |> render("index.json", result)
    else
      {:error, :no_campaign} -> {:error, "No active campaign selected"}
      nil -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :forbidden}
    end
  end

  defp get_current_campaign_id(user) do
    if user.current_campaign_id do
      {:ok, user.current_campaign_id}
    else
      {:error, :no_campaign}
    end
  end

  defp authorize_campaign_access(campaign, user) do
    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      Campaigns.is_member?(campaign.id, user.id) -> :ok
      true -> {:error, :forbidden}
    end
  end
end
