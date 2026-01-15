defmodule ShotElixirWeb.Api.V2.NotionControllerTest do
  @moduledoc """
  Tests for the NotionController Notion integration endpoints.

  Tests cover:
  - Authentication requirements for all endpoints
  - Current campaign validation (user must have current_campaign_id set)
  - Entity search endpoints (sites, parties, factions, junctures, adventures, characters)

  All entity search endpoints require:
  - Authentication (JWT token)
  - User must have a current_campaign_id set
  - Campaign must have Notion connected (notion_access_token)
  - Campaign must have the entity's database configured in notion_database_ids

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
      conn = get(conn, ~p"/api/v2/notion/databases")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/databases")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints
    # that prevent setting a non-existent current_campaign_id on the user

    test "returns 404 when Notion not connected", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: nil
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/databases")

      assert json_response(conn, 404)["error"] == "Notion not connected for this campaign"
    end

    # Note: Testing the success case would require mocking the NotionClient
    # to avoid external API calls. The test would verify:
    # - 200 status when campaign has Notion connected
    # - Response is a list of databases with id and title
  end

  describe "adventures" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/adventures")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints

    test "returns 404 when Notion not connected", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: nil
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures")

      assert json_response(conn, 404)["error"] == "Notion not connected for this campaign"
    end

    test "returns 404 when adventures database not configured", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: "fake-token",
          notion_database_ids: %{}
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures")

      assert json_response(conn, 404)["error"] ==
               "No adventures database configured for this campaign"
    end
  end

  describe "search_sites" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/sites")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/sites")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints

    test "returns 404 when sites database not configured", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: "fake-token",
          notion_database_ids: %{}
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/sites")

      assert json_response(conn, 404)["error"] == "No sites database configured for this campaign"
    end
  end

  describe "search_parties" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/parties")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/parties")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints

    test "returns 404 when parties database not configured", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: "fake-token",
          notion_database_ids: %{}
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/parties")

      assert json_response(conn, 404)["error"] ==
               "No parties database configured for this campaign"
    end
  end

  describe "search_factions" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/factions")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/factions")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints

    test "returns 404 when factions database not configured", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: "fake-token",
          notion_database_ids: %{}
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/factions")

      assert json_response(conn, 404)["error"] ==
               "No factions database configured for this campaign"
    end
  end

  describe "search_junctures" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/junctures")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/junctures")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints

    test "returns 404 when junctures database not configured", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: "fake-token",
          notion_database_ids: %{}
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/junctures")

      assert json_response(conn, 404)["error"] ==
               "No junctures database configured for this campaign"
    end
  end

  describe "search (characters)" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/search")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when no current campaign set", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/search")

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    # Note: "campaign not found" case cannot be tested due to FK constraints

    test "returns 404 when characters database not configured", %{conn: conn, user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          notion_access_token: "fake-token",
          notion_database_ids: %{}
        })

      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/search")

      assert json_response(conn, 404)["error"] ==
               "No characters database configured for this campaign"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
