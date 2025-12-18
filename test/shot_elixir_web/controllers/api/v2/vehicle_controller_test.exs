defmodule ShotElixirWeb.Api.V2.VehicleControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.Vehicles
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Vehicle",
    action_values: %{
      "frame" => 10,
      "handling" => 8,
      "squeal" => 12
    },
    color: "red",
    impairments: 0,
    active: true,
    image_url: "https://example.com/vehicle.jpg",
    task: false,
    summary: "A test vehicle",
    description: %{"text" => "This is a test vehicle"}
  }

  @update_attrs %{
    name: "Updated Vehicle",
    action_values: %{
      "frame" => 12,
      "handling" => 9,
      "squeal" => 14
    },
    color: "blue",
    impairments: 2
  }

  @invalid_attrs %{name: nil, action_values: nil, campaign_id: nil}

  setup %{conn: conn} do
    # Create a gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm_vehicle@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a player user
    {:ok, player} =
      Accounts.create_user(%{
        email: "player_vehicle@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Vehicle Test Campaign",
        description: "Campaign for vehicle testing",
        user_id: gamemaster.id
      })

    # Set current campaign for users
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})
    {:ok, player} = Accounts.update_user(player, %{current_campaign_id: campaign.id})

    # Add player to campaign
    Campaigns.add_member(campaign, player)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gamemaster,
     player: player,
     campaign: campaign}
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all vehicles for current campaign when authenticated", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      # Create some vehicles
      {:ok, vehicle1} =
        Vehicles.create_vehicle(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gamemaster.id,
            name: "Vehicle 1"
          })
        )

      {:ok, vehicle2} =
        Vehicles.create_vehicle(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gamemaster.id,
            name: "Vehicle 2"
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/vehicles")

      assert json_response(conn, 200)["vehicles"]
      vehicles = json_response(conn, 200)["vehicles"]
      assert length(vehicles) == 2
      assert Enum.any?(vehicles, fn v -> v["name"] == "Vehicle 1" end)
      assert Enum.any?(vehicles, fn v -> v["name"] == "Vehicle 2" end)
    end

    test "returns error when no campaign selected", %{conn: conn, gamemaster: gamemaster} do
      # Clear current campaign
      {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: nil})

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/vehicles")

      assert json_response(conn, 422)["error"] == "No active campaign selected"
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v2/vehicles")
      assert conn.status == 401
    end
  end

  describe "archetypes" do
    test "lists vehicle archetypes", %{conn: conn, gamemaster: gamemaster} do
      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/vehicles/archetypes")

      assert json_response(conn, 200)["archetypes"]
      archetypes = json_response(conn, 200)["archetypes"]
      assert is_list(archetypes)
      assert length(archetypes) > 0

      # Check structure of archetype
      first = hd(archetypes)
      assert Map.has_key?(first, "id")
      assert Map.has_key?(first, "name")
      assert Map.has_key?(first, "frame")
      assert Map.has_key?(first, "handling")
    end
  end

  describe "show" do
    setup %{gamemaster: gamemaster, campaign: campaign} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gamemaster.id
          })
        )

      {:ok, vehicle: vehicle}
    end

    test "shows a vehicle when authenticated", %{
      conn: conn,
      gamemaster: gamemaster,
      vehicle: vehicle
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/vehicles/#{vehicle.id}")

      response = json_response(conn, 200)
      assert response["id"] == vehicle.id
      assert response["name"] == vehicle.name
      assert response["action_values"] == vehicle.action_values
    end

    test "returns 404 for non-existent vehicle", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/vehicles/#{fake_id}")

      assert json_response(conn, 404)["error"] == "Vehicle not found"
    end

    test "requires authentication", %{conn: conn, vehicle: vehicle} do
      conn = get(conn, "/api/v2/vehicles/#{vehicle.id}")
      assert conn.status == 401
    end
  end

  describe "create" do
    test "creates vehicle with valid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/vehicles", vehicle: @create_attrs)

      assert %{"id" => id} = json_response(conn, 201)

      # Verify vehicle was created
      vehicle = Vehicles.get_vehicle(id)
      assert vehicle.name == @create_attrs.name
      assert vehicle.campaign_id == campaign.id
      assert vehicle.user_id == gamemaster.id
    end

    test "returns errors with invalid attributes", %{conn: conn, gamemaster: gamemaster} do
      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/vehicles", vehicle: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "requires authentication", %{conn: conn} do
      conn = post(conn, "/api/v2/vehicles", vehicle: @create_attrs)
      assert conn.status == 401
    end

    test "player can create vehicle", %{conn: conn, player: player} do
      conn =
        conn
        |> authenticate(player)
        |> post("/api/v2/vehicles", vehicle: @create_attrs)

      assert %{"id" => _id} = json_response(conn, 201)
    end
  end

  describe "update" do
    setup %{gamemaster: gamemaster, campaign: campaign} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gamemaster.id
          })
        )

      {:ok, vehicle: vehicle}
    end

    test "updates vehicle with valid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      vehicle: vehicle
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/vehicles/#{vehicle.id}", vehicle: @update_attrs)

      response = json_response(conn, 200)
      assert response["id"] == vehicle.id
      assert response["name"] == "Updated Vehicle"
      assert response["color"] == "blue"
      assert response["impairments"] == 2
    end

    test "returns errors with invalid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      vehicle: vehicle
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/vehicles/#{vehicle.id}", vehicle: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns 404 for non-existent vehicle", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/vehicles/#{fake_id}", vehicle: @update_attrs)

      assert json_response(conn, 404)["error"] == "Vehicle not found"
    end

    test "requires authentication", %{conn: conn, vehicle: vehicle} do
      conn = patch(conn, "/api/v2/vehicles/#{vehicle.id}", vehicle: @update_attrs)
      assert conn.status == 401
    end

    test "updates vehicle when params are sent as JSON string (FormData compatibility)", %{
      conn: conn,
      gamemaster: gamemaster,
      vehicle: vehicle
    } do
      # This simulates the frontend sending vehicle params as a JSON string via FormData
      json_string = Jason.encode!(%{name: "JSON String Update", color: "green"})

      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/vehicles/#{vehicle.id}", vehicle: json_string)

      response = json_response(conn, 200)
      assert response["id"] == vehicle.id
      assert response["name"] == "JSON String Update"
      assert response["color"] == "green"
    end
  end

  describe "delete" do
    setup %{gamemaster: gamemaster, campaign: campaign} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gamemaster.id
          })
        )

      {:ok, vehicle: vehicle}
    end

    test "soft deletes vehicle (sets active to false)", %{
      conn: conn,
      gamemaster: gamemaster,
      vehicle: vehicle
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/vehicles/#{vehicle.id}")

      assert response(conn, 204)

      # Verify vehicle is soft deleted
      updated_vehicle = Vehicles.get_vehicle(vehicle.id)
      assert updated_vehicle.active == false
    end

    test "returns 404 for non-existent vehicle", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/vehicles/#{fake_id}")

      assert json_response(conn, 404)["error"] == "Vehicle not found"
    end

    test "requires authentication", %{conn: conn, vehicle: vehicle} do
      conn = delete(conn, "/api/v2/vehicles/#{vehicle.id}")
      assert conn.status == 401
    end
  end
end
