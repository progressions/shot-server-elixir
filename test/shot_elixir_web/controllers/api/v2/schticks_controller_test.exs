defmodule ShotElixirWeb.Api.V2.SchticksControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Schticks
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Schtick",
    description: "A test schtick ability",
    category: "fu",
    path: "Path of the Warrior",
    color: "red",
    image_url: "https://example.com/schtick.jpg",
    bonus: false,
    archetypes: ["martial_artist"],
    active: true
  }

  @update_attrs %{
    name: "Updated Schtick",
    description: "Updated description",
    category: "guns",
    path: "Path of the Gun"
  }

  @invalid_attrs %{name: nil, campaign_id: nil}

  setup %{conn: conn} do
    # Create a gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm_schtick@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a player user
    {:ok, player} =
      Accounts.create_user(%{
        email: "player_schtick@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Schtick Test Campaign",
        description: "Campaign for schtick testing",
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
    test "lists all schticks for current campaign when authenticated", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      # Create some schticks with different categories
      {:ok, _schtick1} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Schtick 1",
            category: "fu",
            path: "Path of the Warrior"
          })
        )

      {:ok, _schtick2} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Schtick 2",
            category: "guns",
            path: "Path of the Gun"
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/schticks")

      response = json_response(conn, 200)
      schticks = response["schticks"]
      assert length(schticks) == 2
      assert Enum.any?(schticks, fn s -> s["name"] == "Schtick 1" end)
      assert Enum.any?(schticks, fn s -> s["name"] == "Schtick 2" end)

      # Verify categories and paths arrays are included
      assert is_list(response["categories"])
      assert is_list(response["paths"])
      assert "fu" in response["categories"]
      assert "guns" in response["categories"]
      assert "Path of the Warrior" in response["paths"]
      assert "Path of the Gun" in response["paths"]
    end

    test "filters schticks by category", %{conn: conn, gamemaster: gamemaster, campaign: campaign} do
      {:ok, _fu} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Fu Schtick",
            category: "fu"
          })
        )

      {:ok, _guns} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Guns Schtick",
            category: "guns"
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/schticks?category=fu")

      schticks = json_response(conn, 200)["schticks"]
      assert length(schticks) == 1
      assert hd(schticks)["name"] == "Fu Schtick"
    end

    test "returns error when no campaign selected", %{conn: conn, gamemaster: gamemaster} do
      # Clear current campaign
      {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: nil})

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/schticks")

      assert json_response(conn, 422)["error"] == "No active campaign selected"
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v2/schticks")
      assert conn.status == 401
    end
  end

  describe "show" do
    setup %{campaign: campaign} do
      {:ok, schtick} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, schtick: schtick}
    end

    test "shows a schtick when authenticated", %{
      conn: conn,
      gamemaster: gamemaster,
      schtick: schtick
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/schticks/#{schtick.id}")

      response = json_response(conn, 200)
      assert response["id"] == schtick.id
      assert response["name"] == schtick.name
      assert response["category"] == schtick.category
      assert response["prerequisite"] == nil
    end

    test "shows schtick with prerequisite", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      {:ok, prereq} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Prerequisite"
          })
        )

      {:ok, schtick} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Advanced",
            prerequisite_id: prereq.id
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/schticks/#{schtick.id}")

      response = json_response(conn, 200)
      assert response["prerequisite"]["id"] == prereq.id
      assert response["prerequisite"]["name"] == "Prerequisite"
    end

    test "returns 404 for non-existent schtick", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/schticks/#{fake_id}")

      assert json_response(conn, 404)["error"] == "Schtick not found"
    end

    test "requires authentication", %{conn: conn, schtick: schtick} do
      conn = get(conn, "/api/v2/schticks/#{schtick.id}")
      assert conn.status == 401
    end
  end

  describe "create" do
    test "creates schtick with valid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/schticks", schtick: @create_attrs)

      assert %{"id" => id} = json_response(conn, 201)

      # Verify schtick was created
      schtick = Schticks.get_schtick(id)
      assert schtick.name == @create_attrs.name
      assert schtick.category == @create_attrs.category
      assert schtick.campaign_id == campaign.id
    end

    test "creates schtick with prerequisite", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      {:ok, prereq} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Basic"
          })
        )

      advanced_attrs =
        Map.put(@create_attrs, :prerequisite_id, prereq.id)
        |> Map.put(:name, "Advanced")

      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/schticks", schtick: advanced_attrs)

      response = json_response(conn, 201)
      assert response["prerequisite_id"] == prereq.id
    end

    test "returns errors with invalid attributes", %{conn: conn, gamemaster: gamemaster} do
      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/schticks", schtick: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "requires authentication", %{conn: conn} do
      conn = post(conn, "/api/v2/schticks", schtick: @create_attrs)
      assert conn.status == 401
    end

    test "player can create schtick", %{conn: conn, player: player} do
      conn =
        conn
        |> authenticate(player)
        |> post("/api/v2/schticks", schtick: @create_attrs)

      assert %{"id" => _id} = json_response(conn, 201)
    end
  end

  describe "update" do
    setup %{campaign: campaign} do
      {:ok, schtick} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, schtick: schtick}
    end

    test "updates schtick with valid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      schtick: schtick
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/schticks/#{schtick.id}", schtick: @update_attrs)

      response = json_response(conn, 200)
      assert response["id"] == schtick.id
      assert response["name"] == "Updated Schtick"
      assert response["category"] == "guns"
      assert response["path"] == "Path of the Gun"
    end

    test "returns errors with invalid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      schtick: schtick
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/schticks/#{schtick.id}", schtick: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns 404 for non-existent schtick", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/schticks/#{fake_id}", schtick: @update_attrs)

      assert json_response(conn, 404)["error"] == "Schtick not found"
    end

    test "requires authentication", %{conn: conn, schtick: schtick} do
      conn = patch(conn, "/api/v2/schticks/#{schtick.id}", schtick: @update_attrs)
      assert conn.status == 401
    end
  end

  describe "delete" do
    setup %{campaign: campaign} do
      {:ok, schtick} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, schtick: schtick}
    end

    test "soft deletes schtick (sets active to false)", %{
      conn: conn,
      gamemaster: gamemaster,
      schtick: schtick
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/schticks/#{schtick.id}")

      assert response(conn, 204)

      # Verify schtick is soft deleted
      updated_schtick = Schticks.get_schtick(schtick.id)
      assert updated_schtick.active == false
    end

    test "prevents deletion of schtick with dependents", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      {:ok, prereq} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Basic"
          })
        )

      {:ok, _dependent} =
        Schticks.create_schtick(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Advanced",
            prerequisite_id: prereq.id
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/schticks/#{prereq.id}")

      assert json_response(conn, 422)["error"] == "Cannot delete schtick with dependent schticks"
    end

    test "returns 404 for non-existent schtick", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/schticks/#{fake_id}")

      assert json_response(conn, 404)["error"] == "Schtick not found"
    end

    test "requires authentication", %{conn: conn, schtick: schtick} do
      conn = delete(conn, "/api/v2/schticks/#{schtick.id}")
      assert conn.status == 401
    end
  end
end
