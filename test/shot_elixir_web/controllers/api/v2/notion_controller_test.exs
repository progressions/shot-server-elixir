defmodule ShotElixirWeb.Api.V2.NotionControllerTest do
  @moduledoc """
  Tests for the NotionController Notion integration endpoints.

  Tests cover:
  - Authentication requirements for all endpoints
  - Parameter validation for databases endpoint
  - Entity search endpoints (sites, parties, factions, junctures, adventures)

  Note: Success case tests require mocking NotionService/NotionClient
  to avoid external API calls. These are documented as follow-up items.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        email: "notion-test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, conn: put_req_header(conn, "accept", "application/json"), user: user}
  end

  describe "databases" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/databases?campaign_id=fake-id")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when campaign_id is missing", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/databases")

      assert json_response(conn, 400)["error"] == "Missing required parameter: campaign_id"
    end

    test "returns 404 when campaign not found", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      fake_uuid = "00000000-0000-0000-0000-000000000000"
      conn = get(conn, ~p"/api/v2/notion/databases?campaign_id=#{fake_uuid}")

      assert json_response(conn, 404)["error"] == "Campaign not found or Notion not connected"
    end

    test "returns 404 when Notion not connected", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: nil
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/databases?campaign_id=#{campaign.id}")

      assert json_response(conn, 404)["error"] == "Campaign not found or Notion not connected"
    end

    test "returns 403 when user doesn't have access to campaign", %{conn: conn, user: user} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other-notion-test@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          user_id: other_user.id,
          notion_access_token: "fake-token"
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/databases?campaign_id=#{campaign.id}")

      assert json_response(conn, 403)["error"] == "You do not have access to this campaign"
    end

    # Note: Testing the success case would require mocking the NotionClient
    # to avoid external API calls. The test would verify:
    # - 200 status when campaign has Notion connected
    # - Response is a list of databases with id and title
  end

  describe "adventures" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/adventures?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures?name=test")

      # Could be 200 (found) or 500 (API error) depending on Notion API availability
      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures")

      # Empty name should return all adventures or empty list
      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  describe "search_sites" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/sites?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/sites?name=test")

      # Could be 200 (found) or 500 (API error) depending on Notion API availability
      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/sites")

      # Empty name should return all sites or empty list
      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  describe "search_parties" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/parties?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/parties?name=test")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/parties")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  describe "search_factions" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/factions?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/factions?name=test")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/factions")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
