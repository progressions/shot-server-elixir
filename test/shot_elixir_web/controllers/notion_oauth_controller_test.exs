defmodule ShotElixirWeb.NotionOAuthControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Factory
  alias ShotElixir.Guardian

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

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
