defmodule ShotElixirWeb.Api.V2.LocationConnectionControllerTest do
  use ShotElixirWeb.ConnCase

  import ShotElixir.Factory

  alias ShotElixir.Fights
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    user = insert(:user, gamemaster: true)
    campaign = insert(:campaign, user: user)
    fight = insert(:fight, campaign: campaign)

    # Create two locations in the fight
    {:ok, location1} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})
    {:ok, location2} = Fights.create_fight_location(fight.id, %{"name" => "Bar"})

    conn =
      conn
      |> authenticate(user)
      |> put_req_header("accept", "application/json")

    {:ok,
     conn: conn,
     user: user,
     campaign: campaign,
     fight: fight,
     location1: location1,
     location2: location2}
  end

  describe "index_for_fight" do
    test "lists all location connections for a fight", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      # Create a connection
      {:ok, _connection} =
        Fights.create_fight_location_connection(fight.id, %{
          "from_location_id" => location1.id,
          "to_location_id" => location2.id
        })

      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/location_connections")
      response = json_response(conn, 200)

      assert length(response["location_connections"]) == 1
      connection = hd(response["location_connections"])
      # Bidirectional connections get normalized, so just verify both locations are present
      location_names = [connection["from_location"]["name"], connection["to_location"]["name"]]
      assert "Kitchen" in location_names
      assert "Bar" in location_names
    end

    test "returns empty list when no connections exist", %{conn: conn, fight: fight} do
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/location_connections")
      response = json_response(conn, 200)

      assert response["location_connections"] == []
    end

    test "returns 404 for non-existent fight", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/fights/#{Ecto.UUID.generate()}/location_connections")
      assert json_response(conn, 404)["error"] == "Fight not found"
    end
  end

  describe "create_for_fight" do
    test "creates a location connection", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => location1.id,
            "to_location_id" => location2.id,
            "bidirectional" => true,
            "label" => "Door"
          }
        })

      response = json_response(conn, 201)
      # Bidirectional connections get normalized so lower UUID is always from_location_id
      # Just verify both locations are present
      assert Enum.sort([response["from_location_id"], response["to_location_id"]]) ==
               Enum.sort([location1.id, location2.id])

      assert response["bidirectional"] == true
      assert response["label"] == "Door"
    end

    test "creates a unidirectional connection", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => location1.id,
            "to_location_id" => location2.id,
            "bidirectional" => false
          }
        })

      response = json_response(conn, 201)
      assert response["bidirectional"] == false
    end

    test "normalizes bidirectional connection order", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      # Create with higher UUID first - should be normalized
      {first_id, second_id} =
        if location1.id > location2.id do
          {location1.id, location2.id}
        else
          {location2.id, location1.id}
        end

      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => first_id,
            "to_location_id" => second_id,
            "bidirectional" => true
          }
        })

      response = json_response(conn, 201)
      # After normalization, from should be the lower UUID
      assert response["from_location_id"] == second_id
      assert response["to_location_id"] == first_id
    end

    test "rejects self-connection", %{conn: conn, fight: fight, location1: location1} do
      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => location1.id,
            "to_location_id" => location1.id
          }
        })

      response = json_response(conn, 422)
      assert response["errors"]["to_location_id"] != nil
    end

    test "rejects connection between locations in different fights", %{
      conn: conn,
      campaign: campaign,
      fight: fight,
      location1: location1
    } do
      # Create another fight with a location
      other_fight = insert(:fight, campaign: campaign)
      {:ok, other_location} = Fights.create_fight_location(other_fight.id, %{"name" => "Patio"})

      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => location1.id,
            "to_location_id" => other_location.id
          }
        })

      response = json_response(conn, 422)
      assert response["error"] =~ "location"
    end

    test "rejects non-gamemaster", %{
      conn: conn,
      fight: fight,
      campaign: campaign,
      location1: location1,
      location2: location2
    } do
      # Create a non-gamemaster user who is a campaign member
      player = insert(:user, gamemaster: false)
      insert(:campaign_user, campaign: campaign, user: player)

      conn =
        conn
        |> authenticate(player)
        |> post(~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => location1.id,
            "to_location_id" => location2.id
          }
        })

      assert json_response(conn, 403)["error"] =~ "gamemaster"
    end

    test "accepts params under location_connection key", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      # Frontend sends params under "location_connection" key
      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/location_connections", %{
          "location_connection" => %{
            "from_location_id" => location1.id,
            "to_location_id" => location2.id,
            "bidirectional" => true,
            "label" => "Stairs"
          }
        })

      response = json_response(conn, 201)

      assert Enum.sort([response["from_location_id"], response["to_location_id"]]) ==
               Enum.sort([location1.id, location2.id])

      assert response["bidirectional"] == true
      assert response["label"] == "Stairs"
    end
  end

  describe "show" do
    test "returns a connection by ID", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      {:ok, connection} =
        Fights.create_fight_location_connection(fight.id, %{
          "from_location_id" => location1.id,
          "to_location_id" => location2.id
        })

      conn = get(conn, ~p"/api/v2/location_connections/#{connection.id}")
      response = json_response(conn, 200)

      assert response["id"] == connection.id
      # Bidirectional connections get normalized, so just verify both locations are present
      location_names = [response["from_location"]["name"], response["to_location"]["name"]]
      assert "Kitchen" in location_names
      assert "Bar" in location_names
    end

    test "returns 404 for non-existent connection", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/location_connections/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "Connection not found"
    end
  end

  describe "delete" do
    test "deletes a connection", %{
      conn: conn,
      fight: fight,
      location1: location1,
      location2: location2
    } do
      {:ok, connection} =
        Fights.create_fight_location_connection(fight.id, %{
          "from_location_id" => location1.id,
          "to_location_id" => location2.id
        })

      conn = delete(conn, ~p"/api/v2/location_connections/#{connection.id}")
      assert response(conn, 204)

      # Verify deletion
      assert Fights.get_location_connection(connection.id) == nil
    end

    test "returns 404 for non-existent connection", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/location_connections/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["error"] == "Connection not found"
    end

    test "rejects non-gamemaster", %{
      conn: conn,
      fight: fight,
      campaign: campaign,
      location1: location1,
      location2: location2
    } do
      {:ok, connection} =
        Fights.create_fight_location_connection(fight.id, %{
          "from_location_id" => location1.id,
          "to_location_id" => location2.id
        })

      player = insert(:user, gamemaster: false)
      insert(:campaign_user, campaign: campaign, user: player)

      conn =
        conn
        |> authenticate(player)
        |> delete(~p"/api/v2/location_connections/#{connection.id}")

      assert json_response(conn, 403)["error"] =~ "gamemaster"
    end
  end

  describe "site location connections" do
    setup %{campaign: campaign} do
      site = insert(:site, campaign: campaign)
      {:ok, site_loc1} = Fights.create_site_location(site.id, %{"name" => "Room A"})
      {:ok, site_loc2} = Fights.create_site_location(site.id, %{"name" => "Room B"})

      {:ok, site: site, site_loc1: site_loc1, site_loc2: site_loc2}
    end

    test "lists connections for a site", %{
      conn: conn,
      site: site,
      site_loc1: site_loc1,
      site_loc2: site_loc2
    } do
      {:ok, _connection} =
        Fights.create_site_location_connection(site.id, %{
          "from_location_id" => site_loc1.id,
          "to_location_id" => site_loc2.id
        })

      conn = get(conn, ~p"/api/v2/sites/#{site.id}/location_connections")
      response = json_response(conn, 200)

      assert length(response["location_connections"]) == 1
    end

    test "creates a connection for a site", %{
      conn: conn,
      site: site,
      site_loc1: site_loc1,
      site_loc2: site_loc2
    } do
      conn =
        post(conn, ~p"/api/v2/sites/#{site.id}/location_connections", %{
          "connection" => %{
            "from_location_id" => site_loc1.id,
            "to_location_id" => site_loc2.id,
            "label" => "Hallway"
          }
        })

      response = json_response(conn, 201)
      assert response["label"] == "Hallway"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
