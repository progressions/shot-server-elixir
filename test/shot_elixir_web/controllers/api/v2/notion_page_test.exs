defmodule ShotElixirWeb.Api.V2.NotionPageTest do
  @moduledoc """
  Tests for the /notion_page endpoint across all entity types.
  These endpoints return raw Notion page JSON for debugging Notion sync issues.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{
    Accounts,
    Adventures,
    Campaigns,
    Characters,
    Factions,
    Guardian,
    Junctures,
    Parties,
    Sites
  }

  setup %{conn: conn} do
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, player} =
      Accounts.create_user(%{
        email: "player@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign",
        user_id: gamemaster.id
      })

    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)
    {:ok, _} = Campaigns.add_member(campaign, player)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     player: player_with_campaign,
     campaign: campaign}
  end

  describe "GET /api/v2/characters/:id/notion_page" do
    test "returns 404 when character has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/notion_page")

      assert json_response(conn, 404)["error"] == "Character has no linked Notion page"
    end

    test "returns 404 when character not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{Ecto.UUID.generate()}/notion_page")

      assert json_response(conn, 404)["error"]
    end

    test "requires authentication", %{conn: conn, campaign: campaign, gamemaster: gm} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: gm.id
        })

      conn = get(conn, ~p"/api/v2/characters/#{character.id}/notion_page")
      assert json_response(conn, 401)
    end
  end

  describe "GET /api/v2/sites/:id/notion_page" do
    test "returns 404 when site has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, site} =
        Sites.create_site(%{
          name: "Test Site",
          campaign_id: campaign.id,
          attunement: 5
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/sites/#{site.id}/notion_page")

      assert json_response(conn, 404)["error"] == "Site has no linked Notion page"
    end

    test "returns 404 when site not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/sites/#{Ecto.UUID.generate()}/notion_page")

      assert json_response(conn, 404)["error"]
    end
  end

  describe "GET /api/v2/parties/:id/notion_page" do
    test "returns 404 when party has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, party} =
        Parties.create_party(%{
          name: "Test Party",
          campaign_id: campaign.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/parties/#{party.id}/notion_page")

      assert json_response(conn, 404)["error"] == "Party has no linked Notion page"
    end

    test "returns 404 when party not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}/notion_page")

      assert json_response(conn, 404)["error"]
    end
  end

  describe "GET /api/v2/factions/:id/notion_page" do
    test "returns 404 when faction has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Test Faction",
          campaign_id: campaign.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/factions/#{faction.id}/notion_page")

      assert json_response(conn, 404)["error"] == "Faction has no linked Notion page"
    end

    test "returns 404 when faction not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/factions/#{Ecto.UUID.generate()}/notion_page")

      assert json_response(conn, 404)["error"]
    end
  end

  describe "GET /api/v2/junctures/:id/notion_page" do
    test "returns 404 when juncture has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Test Juncture",
          campaign_id: campaign.id,
          year: 2025,
          time_period: "Contemporary"
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/junctures/#{juncture.id}/notion_page")

      assert json_response(conn, 404)["error"] == "Juncture has no linked Notion page"
    end

    test "returns 404 when juncture not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/junctures/#{Ecto.UUID.generate()}/notion_page")

      assert json_response(conn, 404)["error"]
    end
  end

  describe "GET /api/v2/adventures/:id/notion_page" do
    test "returns 404 when adventure has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: gm.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/adventures/#{adventure.id}/notion_page")

      assert json_response(conn, 404)["error"] == "Adventure has no linked Notion page"
    end

    test "returns 404 when adventure not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/adventures/#{Ecto.UUID.generate()}/notion_page")

      assert json_response(conn, 404)["error"]
    end
  end

  describe "campaign access control" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User",
          gamemaster: false
        })

      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "Not the test campaign",
          user_id: other_user.id
        })

      {:ok, other_with_campaign} = Accounts.set_current_campaign(other_user, other_campaign.id)

      {:ok, character} =
        Characters.create_character(%{
          name: "Protected Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, other_user: other_with_campaign, other_campaign: other_campaign, character: character}
    end

    test "denies access to users not in the campaign", %{
      conn: conn,
      other_user: other_user,
      character: character
    } do
      conn = authenticate(conn, other_user)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/notion_page")

      assert json_response(conn, 403)["error"] == "Access denied"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
