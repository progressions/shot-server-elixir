defmodule ShotElixirWeb.Api.V2.LocationControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Sites, Fights, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm-location@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a regular player user
    {:ok, player} =
      Accounts.create_user(%{
        email: "player-location@test.com",
        password: "password123",
        first_name: "Regular",
        last_name: "Player",
        gamemaster: false
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Location Test Campaign",
        description: "Campaign for location testing",
        user_id: gamemaster.id
      })

    # Add player as member
    {:ok, _membership} = Campaigns.add_member(campaign, player)

    # Set current campaign for both users
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})
    {:ok, player} = Accounts.update_user(player, %{current_campaign_id: campaign.id})

    # Create a fight
    {:ok, fight} =
      Fights.create_fight(%{
        name: "Test Fight",
        campaign_id: campaign.id
      })

    # Create a site
    {:ok, site} =
      Sites.create_site(%{
        name: "Test Site",
        campaign_id: campaign.id
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")

    %{
      conn: conn,
      gamemaster: gamemaster,
      player: player,
      campaign: campaign,
      fight: fight,
      site: site
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index_for_fight" do
    test "lists all locations for a fight", %{conn: conn, gamemaster: gm, fight: fight} do
      {:ok, location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(gm)
        |> get(~p"/api/v2/fights/#{fight.id}/locations")

      assert %{"locations" => [returned_location]} = json_response(conn, 200)
      assert returned_location["id"] == location.id
      assert returned_location["name"] == "Kitchen"
    end

    test "returns empty list when no locations", %{conn: conn, gamemaster: gm, fight: fight} do
      conn =
        conn
        |> authenticate(gm)
        |> get(~p"/api/v2/fights/#{fight.id}/locations")

      assert %{"locations" => []} = json_response(conn, 200)
    end

    test "player can view fight locations", %{conn: conn, player: player, fight: fight} do
      {:ok, _location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(player)
        |> get(~p"/api/v2/fights/#{fight.id}/locations")

      assert %{"locations" => [_]} = json_response(conn, 200)
    end

    test "returns 404 for non-existent fight", %{conn: conn, gamemaster: gm} do
      conn =
        conn
        |> authenticate(gm)
        |> get(~p"/api/v2/fights/#{Ecto.UUID.generate()}/locations")

      assert json_response(conn, 404)["error"] == "Fight not found"
    end
  end

  describe "index_for_site" do
    test "lists all locations for a site", %{conn: conn, gamemaster: gm, site: site} do
      {:ok, location} = Fights.create_site_location(site.id, %{"name" => "Entrance"})

      conn =
        conn
        |> authenticate(gm)
        |> get(~p"/api/v2/sites/#{site.id}/locations")

      assert %{"locations" => [returned_location]} = json_response(conn, 200)
      assert returned_location["id"] == location.id
      assert returned_location["name"] == "Entrance"
    end
  end

  describe "create_for_fight" do
    test "gamemaster can create location for fight", %{conn: conn, gamemaster: gm, fight: fight} do
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/fights/#{fight.id}/locations", %{
          location: %{name: "Kitchen", color: "#ff0000"}
        })

      assert %{"name" => "Kitchen", "color" => "#ff0000"} = json_response(conn, 201)
    end

    test "player cannot create location", %{conn: conn, player: player, fight: fight} do
      conn =
        conn
        |> authenticate(player)
        |> post(~p"/api/v2/fights/#{fight.id}/locations", %{
          location: %{name: "Kitchen"}
        })

      assert json_response(conn, 403)["error"] == "Only gamemaster can create locations"
    end

    test "validates required name", %{conn: conn, gamemaster: gm, fight: fight} do
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/fights/#{fight.id}/locations", %{
          location: %{color: "#ff0000"}
        })

      assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
    end

    test "prevents duplicate names (case-insensitive)", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      {:ok, _} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/fights/#{fight.id}/locations", %{
          location: %{name: "KITCHEN"}
        })

      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "create_for_site" do
    test "gamemaster can create location for site", %{conn: conn, gamemaster: gm, site: site} do
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/sites/#{site.id}/locations", %{
          location: %{name: "Entrance", description: "Main entrance"}
        })

      assert %{"name" => "Entrance", "description" => "Main entrance"} = json_response(conn, 201)
    end
  end

  describe "show" do
    test "returns location details", %{conn: conn, gamemaster: gm, fight: fight} do
      {:ok, location} =
        Fights.create_fight_location(fight.id, %{
          "name" => "Kitchen",
          "color" => "#ff0000",
          "description" => "A kitchen"
        })

      conn =
        conn
        |> authenticate(gm)
        |> get(~p"/api/v2/locations/#{location.id}")

      response = json_response(conn, 200)
      assert response["id"] == location.id
      assert response["name"] == "Kitchen"
      assert response["color"] == "#ff0000"
      assert response["description"] == "A kitchen"
    end

    test "returns 404 for non-existent location", %{conn: conn, gamemaster: gm} do
      conn =
        conn
        |> authenticate(gm)
        |> get(~p"/api/v2/locations/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] == "Location not found"
    end
  end

  describe "update" do
    test "gamemaster can update location", %{conn: conn, gamemaster: gm, fight: fight} do
      {:ok, location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(gm)
        |> patch(~p"/api/v2/locations/#{location.id}", %{
          location: %{name: "Updated Kitchen", color: "#00ff00"}
        })

      response = json_response(conn, 200)
      assert response["name"] == "Updated Kitchen"
      assert response["color"] == "#00ff00"
    end

    test "player cannot update location", %{conn: conn, player: player, fight: fight} do
      {:ok, location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(player)
        |> patch(~p"/api/v2/locations/#{location.id}", %{
          location: %{name: "Updated"}
        })

      assert json_response(conn, 403)["error"] == "Only gamemaster can update locations"
    end
  end

  describe "delete" do
    test "gamemaster can delete location", %{conn: conn, gamemaster: gm, fight: fight} do
      {:ok, location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(gm)
        |> delete(~p"/api/v2/locations/#{location.id}")

      assert response(conn, 204)
      assert Fights.get_location(location.id) == nil
    end

    test "player cannot delete location", %{conn: conn, player: player, fight: fight} do
      {:ok, location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(player)
        |> delete(~p"/api/v2/locations/#{location.id}")

      assert json_response(conn, 403)["error"] == "Only gamemaster can delete locations"
    end
  end
end
