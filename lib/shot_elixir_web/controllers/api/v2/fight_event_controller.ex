defmodule ShotElixirWeb.Api.V2.FightEventController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  GET /api/v2/fights/:fight_id/fight_events

  Lists all fight events for a given fight, ordered chronologically.
  Requires user to have access to the fight's campaign.
  """
  def index(conn, %{"fight_id" => fight_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Fights.get_fight(fight_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      fight ->
        # Check campaign access
        case Campaigns.get_campaign(fight.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Fight not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              fight_events = Fights.list_fight_events(fight_id)

              conn
              |> put_view(ShotElixirWeb.Api.V2.FightEventView)
              |> render("index.json", fight_events: fight_events)
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Access denied"})
            end
        end
    end
  end

  # Private helper functions
  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
      Campaigns.is_member?(campaign.id, user.id)
  end
end
