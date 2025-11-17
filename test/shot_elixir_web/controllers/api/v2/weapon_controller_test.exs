defmodule ShotElixirWeb.Api.V2.WeaponControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Weapons
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Pistol",
    description: "A standard pistol",
    damage: 10,
    concealment: 3,
    reload_value: 1,
    juncture: "Contemporary",
    mook_bonus: 0,
    category: "guns",
    kachunk: false,
    image_url: "https://example.com/pistol.jpg",
    active: true
  }

  @update_attrs %{
    name: "Updated Pistol",
    damage: 12,
    concealment: 2,
    category: "heavy"
  }

  @invalid_attrs %{name: nil, damage: nil, campaign_id: nil}

  setup %{conn: conn} do
    # Create a gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm_weapon@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a player user
    {:ok, player} =
      Accounts.create_user(%{
        email: "player_weapon@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Weapon Test Campaign",
        description: "Campaign for weapon testing",
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
    test "lists all weapons for current campaign when authenticated", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      # Create some weapons
      {:ok, _weapon1} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Pistol 1"
          })
        )

      {:ok, _weapon2} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Rifle 2"
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/weapons")

      assert json_response(conn, 200)["weapons"]
      weapons = json_response(conn, 200)["weapons"]
      assert length(weapons) == 2
      assert Enum.any?(weapons, fn w -> w["name"] == "Pistol 1" end)
      assert Enum.any?(weapons, fn w -> w["name"] == "Rifle 2" end)
    end

    test "filters weapons by category", %{conn: conn, gamemaster: gamemaster, campaign: campaign} do
      {:ok, _gun} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Gun",
            category: "guns"
          })
        )

      {:ok, _sword} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            name: "Sword",
            category: "melee"
          })
        )

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/weapons?category=melee")

      weapons = json_response(conn, 200)["weapons"]
      assert length(weapons) == 1
      assert hd(weapons)["name"] == "Sword"
    end

    test "returns error when no campaign selected", %{conn: conn, gamemaster: gamemaster} do
      # Clear current campaign
      {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: nil})

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/weapons")

      assert json_response(conn, 422)["error"] == "No active campaign selected"
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, "/api/v2/weapons")
      assert conn.status == 401
    end
  end

  describe "show" do
    setup %{gamemaster: gamemaster, campaign: campaign} do
      {:ok, weapon} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, weapon: weapon}
    end

    test "shows a weapon when authenticated", %{
      conn: conn,
      gamemaster: gamemaster,
      weapon: weapon
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/weapons/#{weapon.id}")

      response = json_response(conn, 200)
      assert response["id"] == weapon.id
      assert response["name"] == weapon.name
      assert response["damage"] == weapon.damage
      assert response["concealment"] == weapon.concealment
    end

    test "returns 404 for non-existent weapon", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> get("/api/v2/weapons/#{fake_id}")

      assert json_response(conn, 404)["error"] == "Weapon not found"
    end

    test "requires authentication", %{conn: conn, weapon: weapon} do
      conn = get(conn, "/api/v2/weapons/#{weapon.id}")
      assert conn.status == 401
    end
  end

  describe "create" do
    test "creates weapon with valid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      campaign: campaign
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/weapons", weapon: @create_attrs)

      assert %{"id" => id} = json_response(conn, 201)

      # Verify weapon was created
      weapon = Weapons.get_weapon(id)
      assert weapon.name == @create_attrs.name
      assert weapon.damage == @create_attrs.damage
      assert weapon.campaign_id == campaign.id
    end

    test "returns errors with invalid attributes", %{conn: conn, gamemaster: gamemaster} do
      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/weapons", weapon: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "validates concealment range", %{conn: conn, gamemaster: gamemaster} do
      invalid_concealment = Map.put(@create_attrs, :concealment, 10)

      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/weapons", weapon: invalid_concealment)

      errors = json_response(conn, 422)["errors"]
      assert errors["concealment"] != nil
    end

    test "validates category values", %{conn: conn, gamemaster: gamemaster} do
      invalid_category = Map.put(@create_attrs, :category, "invalid_category")

      conn =
        conn
        |> authenticate(gamemaster)
        |> post("/api/v2/weapons", weapon: invalid_category)

      errors = json_response(conn, 422)["errors"]
      assert errors["category"] != nil
    end

    test "requires authentication", %{conn: conn} do
      conn = post(conn, "/api/v2/weapons", weapon: @create_attrs)
      assert conn.status == 401
    end

    test "player can create weapon", %{conn: conn, player: player} do
      conn =
        conn
        |> authenticate(player)
        |> post("/api/v2/weapons", weapon: @create_attrs)

      assert %{"id" => _id} = json_response(conn, 201)
    end
  end

  describe "update" do
    setup %{gamemaster: gamemaster, campaign: campaign} do
      {:ok, weapon} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, weapon: weapon}
    end

    test "updates weapon with valid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      weapon: weapon
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/weapons/#{weapon.id}", weapon: @update_attrs)

      response = json_response(conn, 200)
      assert response["id"] == weapon.id
      assert response["name"] == "Updated Pistol"
      assert response["damage"] == 12
      assert response["concealment"] == 2
      assert response["category"] == "heavy"
    end

    test "returns errors with invalid attributes", %{
      conn: conn,
      gamemaster: gamemaster,
      weapon: weapon
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/weapons/#{weapon.id}", weapon: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns 404 for non-existent weapon", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> patch("/api/v2/weapons/#{fake_id}", weapon: @update_attrs)

      assert json_response(conn, 404)["error"] == "Weapon not found"
    end

    test "requires authentication", %{conn: conn, weapon: weapon} do
      conn = patch(conn, "/api/v2/weapons/#{weapon.id}", weapon: @update_attrs)
      assert conn.status == 401
    end
  end

  describe "delete" do
    setup %{gamemaster: gamemaster, campaign: campaign} do
      {:ok, weapon} =
        Weapons.create_weapon(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, weapon: weapon}
    end

    test "soft deletes weapon (sets active to false)", %{
      conn: conn,
      gamemaster: gamemaster,
      weapon: weapon
    } do
      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/weapons/#{weapon.id}")

      assert response(conn, 204)

      # Verify weapon is soft deleted
      updated_weapon = Weapons.get_weapon(weapon.id)
      assert updated_weapon.active == false
    end

    test "returns 404 for non-existent weapon", %{conn: conn, gamemaster: gamemaster} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(gamemaster)
        |> delete("/api/v2/weapons/#{fake_id}")

      assert json_response(conn, 404)["error"] == "Weapon not found"
    end

    test "requires authentication", %{conn: conn, weapon: weapon} do
      conn = delete(conn, "/api/v2/weapons/#{weapon.id}")
      assert conn.status == 401
    end
  end
end
