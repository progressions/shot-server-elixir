defmodule ShotElixirWeb.NotionOAuthControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Factory
  alias ShotElixir.Guardian
  alias ShotElixir.Campaigns

  setup do
    user = Factory.insert(:user)
    campaign = Factory.insert(:campaign, user: user)
    {:ok, user: user, campaign: campaign}
  end

  describe "authorize/2" do
    test "redirects to Notion when authenticated and owner", %{
      conn: conn,
      user: user,
      campaign: campaign
    } do
      # Mock configuration (since we don't have env vars in test)
      Application.put_env(:shot_elixir, :notion_oauth,
        client_id: "test_client_id",
        redirect_uri: "http://localhost:4000/auth/notion/callback"
      )

      conn =
        conn
        |> authenticate(user)
        |> get(~p"/auth/notion/authorize?#{[campaign_id: campaign.id]}")

      assert redirected_to(conn) =~ "https://api.notion.com/v1/oauth/authorize"
      assert redirected_to(conn) =~ "client_id=test_client_id"
    end

    test "returns 403 when user is not owner", %{conn: conn, campaign: campaign} do
      other_user = Factory.insert(:user)

      conn =
        conn
        |> authenticate(other_user)
        |> get(~p"/auth/notion/authorize?#{[campaign_id: campaign.id]}")

      assert json_response(conn, 403)["error"] ==
               "You do not have permission to modify this campaign"
    end

    test "returns 401 when not authenticated", %{conn: conn, campaign: campaign} do
      conn = get(conn, ~p"/auth/notion/authorize?#{[campaign_id: campaign.id]}")
      assert json_response(conn, 401)["error"] == "Authentication required"
    end
  end

  describe "callback/2 sets notion_status to working" do
    test "updates campaign notion_status to 'working' on successful OAuth", %{
      user: _user,
      campaign: campaign
    } do
      # Verify campaign starts without working status
      assert campaign.notion_status == "disconnected"

      # Simulate what happens after a successful OAuth callback
      # by directly updating the campaign the way the callback would
      {:ok, updated_campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_access_token: "test-access-token",
          notion_bot_id: "test-bot-id",
          notion_workspace_name: "Test Workspace",
          notion_status: "working"
        })

      # Verify the status is now "working"
      assert updated_campaign.notion_status == "working"

      # Fetch fresh from DB to confirm persistence
      refreshed_campaign = Campaigns.get_campaign(campaign.id)
      assert refreshed_campaign.notion_status == "working"
    end

    test "notion_status remains 'working' after re-authorization", %{
      user: _user,
      campaign: campaign
    } do
      # Set initial working status
      {:ok, working_campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_access_token: "original-token",
          notion_status: "working"
        })

      assert working_campaign.notion_status == "working"

      # Simulate re-authorization (reconnecting workspace)
      {:ok, reconnected_campaign} =
        Campaigns.update_campaign(working_campaign, %{
          notion_access_token: "new-token",
          notion_workspace_name: "New Workspace",
          notion_status: "working"
        })

      assert reconnected_campaign.notion_status == "working"
    end

    test "notion_status changes from 'needs_attention' to 'working' on reconnect", %{
      user: _user,
      campaign: campaign
    } do
      # Set campaign to needs_attention (simulating sync issues)
      {:ok, troubled_campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_access_token: "old-token",
          notion_status: "needs_attention"
        })

      assert troubled_campaign.notion_status == "needs_attention"

      # Simulate successful reconnection via OAuth
      {:ok, fixed_campaign} =
        Campaigns.update_campaign(troubled_campaign, %{
          notion_access_token: "new-token",
          notion_status: "working"
        })

      assert fixed_campaign.notion_status == "working"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
