defmodule ShotElixirWeb.Api.V2.CampaignControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Campaigns
  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Campaign",
    description: "A test campaign for testing",
    active: true
  }

  @update_attrs %{
    name: "Updated Campaign",
    description: "Updated description",
    active: false
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

    {:ok, other_gm} =
      Accounts.create_user(%{
        email: "other_gm@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "GM",
        gamemaster: true
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gamemaster,
     player: player,
     other_gm: other_gm}
  end

  describe "index" do
    test "lists all user's campaigns when authenticated", %{conn: conn, gamemaster: gm} do
      {:ok, campaign1} =
        Campaigns.create_campaign(%{
          name: "Campaign 1",
          description: "First campaign",
          user_id: gm.id
        })

      {:ok, campaign2} =
        Campaigns.create_campaign(%{
          name: "Campaign 2",
          description: "Second campaign",
          user_id: gm.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns")
      response = json_response(conn, 200)

      assert is_list(response["campaigns"])
      assert length(response["campaigns"]) >= 2

      campaign_names = Enum.map(response["campaigns"], & &1["name"])
      assert "Campaign 1" in campaign_names
      assert "Campaign 2" in campaign_names
    end

    test "includes campaigns where user is a member", %{
      conn: conn,
      gamemaster: gm,
      player: player
    } do
      {:ok, owned_campaign} =
        Campaigns.create_campaign(%{
          name: "Player's Campaign",
          description: "Campaign owned by player",
          user_id: player.id
        })

      {:ok, gm_campaign} =
        Campaigns.create_campaign(%{
          name: "GM's Campaign",
          description: "Campaign owned by GM",
          user_id: gm.id
        })

      # Add player as member to GM's campaign
      {:ok, _} = Campaigns.add_member(gm_campaign, player)

      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/campaigns")
      response = json_response(conn, 200)

      campaign_names = Enum.map(response["campaigns"], & &1["name"])
      assert "Player's Campaign" in campaign_names
      assert "GM's Campaign" in campaign_names
    end

    test "returns unauthorized when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/campaigns")
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "show" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          description: "A test campaign",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "returns campaign when user is owner", %{conn: conn, gamemaster: gm, campaign: campaign} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}")
      response = json_response(conn, 200)

      assert response["campaign"]["id"] == campaign.id
      assert response["campaign"]["name"] == campaign.name
      assert response["campaign"]["description"] == campaign.description
    end

    test "returns campaign when user is member", %{conn: conn, player: player, campaign: campaign} do
      {:ok, _} = Campaigns.add_member(campaign, player)

      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}")
      response = json_response(conn, 200)

      assert response["campaign"]["id"] == campaign.id
    end

    test "returns forbidden when user has no access", %{
      conn: conn,
      other_gm: other_gm,
      campaign: campaign
    } do
      conn = authenticate(conn, other_gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns not found for invalid id", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/campaigns/#{invalid_id}")
      assert json_response(conn, 404)["error"] == "Not found"
    end
  end

  describe "create" do
    test "creates campaign when data is valid", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/campaigns", campaign: @create_attrs)
      response = json_response(conn, 201)

      assert response["campaign"]["name"] == "Test Campaign"
      assert response["campaign"]["description"] == "A test campaign for testing"
      assert response["campaign"]["active"] == true
      assert response["campaign"]["user_id"] == gm.id
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/campaigns", campaign: %{name: nil})
      assert json_response(conn, 422)["errors"]
    end

    test "enforces unique name per user", %{conn: conn, gamemaster: gm} do
      # Create first campaign
      authenticated_conn = authenticate(conn, gm)
      first_conn = post(authenticated_conn, ~p"/api/v2/campaigns", campaign: @create_attrs)
      assert json_response(first_conn, 201)

      # Try to create second with same name (use fresh conn)
      second_conn = authenticate(conn, gm)
      duplicate_conn = post(second_conn, ~p"/api/v2/campaigns", campaign: @create_attrs)
      assert json_response(duplicate_conn, 422)["errors"]["name"]
    end

    test "returns unauthorized when not authenticated", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/campaigns", campaign: @create_attrs)
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "update" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Original Campaign",
          description: "Original description",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "updates campaign when user is owner", %{conn: conn, gamemaster: gm, campaign: campaign} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/campaigns/#{campaign.id}", campaign: @update_attrs)
      response = json_response(conn, 200)

      assert response["campaign"]["id"] == campaign.id
      assert response["campaign"]["name"] == "Updated Campaign"
      assert response["campaign"]["description"] == "Updated description"
      assert response["campaign"]["active"] == false
    end

    test "returns forbidden when user is not owner", %{
      conn: conn,
      player: player,
      campaign: campaign
    } do
      # Even if player is a member, they can't update
      {:ok, _} = Campaigns.add_member(campaign, player)

      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/campaigns/#{campaign.id}", campaign: @update_attrs)
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm, campaign: campaign} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/campaigns/#{campaign.id}", campaign: %{name: nil})
      assert json_response(conn, 422)["errors"]
    end

    test "returns not found for invalid id", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = patch(conn, ~p"/api/v2/campaigns/#{invalid_id}", campaign: @update_attrs)
      assert json_response(conn, 404)["error"] == "Not found"
    end
  end

  describe "delete" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Campaign to Delete",
          description: "Will be deleted",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "soft deletes campaign when user is owner", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/campaigns/#{campaign.id}")
      assert response(conn, 204)

      # Verify campaign is soft deleted (active = false)
      deleted_campaign = Campaigns.get_campaign(campaign.id)
      assert deleted_campaign.active == false
    end

    test "returns forbidden when user is not owner", %{
      conn: conn,
      player: player,
      campaign: campaign
    } do
      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/campaigns/#{campaign.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns not found for invalid id", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/v2/campaigns/#{invalid_id}")
      assert json_response(conn, 404)["error"] == "Not found"
    end
  end

  describe "set current campaign" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Campaign to Set",
          description: "Will be set as current",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "sets campaign as current for user", %{conn: conn, gamemaster: gm, campaign: campaign} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/campaigns/#{campaign.id}/set")
      response = json_response(conn, 200)

      assert response["campaign"]["id"] == campaign.id
      assert response["user"]["current_campaign_id"] == campaign.id

      # Verify in database
      updated_user = Accounts.get_user!(gm.id)
      assert updated_user.current_campaign_id == campaign.id
    end

    test "allows member to set campaign as current", %{
      conn: conn,
      player: player,
      campaign: campaign
    } do
      {:ok, _} = Campaigns.add_member(campaign, player)

      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/campaigns/#{campaign.id}/set")
      response = json_response(conn, 200)

      assert response["user"]["current_campaign_id"] == campaign.id
    end

    test "returns forbidden when user has no access", %{
      conn: conn,
      other_gm: other_gm,
      campaign: campaign
    } do
      conn = authenticate(conn, other_gm)
      conn = patch(conn, ~p"/api/v2/campaigns/#{campaign.id}/set")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end
  end

  describe "set_current via POST" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Campaign for POST",
          description: "Set via POST endpoint",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "sets current campaign via POST endpoint", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/campaigns/current", %{campaign_id: campaign.id})
      response = json_response(conn, 200)

      assert response["campaign"]["id"] == campaign.id
      assert response["user"]["current_campaign_id"] == campaign.id
    end
  end

  describe "current_fight" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Campaign with Fight",
          description: "Has a fight",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "returns current fight for campaign", %{conn: conn, gamemaster: gm, campaign: campaign} do
      # Create and start a fight for the campaign
      {:ok, fight} =
        ShotElixir.Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id,
          started_at: DateTime.utc_now()
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}/current_fight")
      response = json_response(conn, 200)

      # Response is the fight directly, not wrapped
      assert response["id"] == fight.id
      assert response["name"] == "Test Fight"
      assert response["campaign_id"] == campaign.id
    end

    test "returns nil when no active fight", %{conn: conn, gamemaster: gm, campaign: campaign} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}/current_fight")
      response = json_response(conn, 200)

      # Response is nil directly when no fight
      assert response == nil
    end
  end

  describe "add_member" do
    setup %{gamemaster: gm} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Campaign for Members",
          description: "Testing membership",
          user_id: gm.id
        })

      %{campaign: campaign}
    end

    test "adds user as campaign member", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      player: player
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/campaigns/#{campaign.id}/members", %{user_id: player.id})
      response = json_response(conn, 201)

      assert response["membership"]["user_id"] == player.id
      assert response["membership"]["campaign_id"] == campaign.id

      # Verify membership exists
      campaigns = Campaigns.get_user_campaigns(player.id)
      assert Enum.any?(campaigns, fn c -> c.id == campaign.id end)
    end

    test "returns forbidden when not owner", %{
      conn: conn,
      player: player,
      campaign: campaign,
      other_gm: other_gm
    } do
      conn = authenticate(conn, player)
      conn = post(conn, ~p"/api/v2/campaigns/#{campaign.id}/members", %{user_id: other_gm.id})
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns error for duplicate membership", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      player: player
    } do
      # Add member first time
      {:ok, _} = Campaigns.add_member(campaign, player)

      # Try to add again
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/campaigns/#{campaign.id}/members", %{user_id: player.id})
      assert json_response(conn, 422)
    end
  end

  describe "remove_member" do
    setup %{gamemaster: gm, player: player} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Campaign with Member",
          description: "Has a member to remove",
          user_id: gm.id
        })

      {:ok, _} = Campaigns.add_member(campaign, player)

      %{campaign: campaign}
    end

    test "removes user from campaign", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      player: player
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/campaigns/#{campaign.id}/members/#{player.id}")
      assert response(conn, 204)

      # Verify membership removed
      campaigns = Campaigns.get_user_campaigns(player.id)
      refute Enum.any?(campaigns, fn c -> c.id == campaign.id end)
    end

    test "returns forbidden when not owner", %{conn: conn, player: player, campaign: campaign} do
      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/campaigns/#{campaign.id}/members/#{player.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns 204 even if member doesn't exist", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      other_gm: other_gm
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/campaigns/#{campaign.id}/members/#{other_gm.id}")
      assert response(conn, 204)
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
