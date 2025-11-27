defmodule ShotElixirWeb.Api.V2.CharacterWeaponControllerTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.{Characters, Campaigns, Accounts, Weapons}
  alias ShotElixir.Guardian

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

    {:ok, other_user} =
      Accounts.create_user(%{
        email: "other@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "User",
        gamemaster: false
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign for character weapons",
        user_id: gamemaster.id
      })

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: player.id,
        action_values: %{"Type" => "PC"}
      })

    {:ok, weapon} =
      Weapons.create_weapon(%{
        name: "Test Pistol",
        description: "A test pistol",
        campaign_id: campaign.id,
        damage: "9",
        concealment: "2"
      })

    {:ok, weapon2} =
      Weapons.create_weapon(%{
        name: "Test Sword",
        description: "A test sword",
        campaign_id: campaign.id,
        damage: "10",
        concealment: "5"
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gamemaster,
     player: player,
     other_user: other_user,
     campaign: campaign,
     character: character,
     weapon: weapon,
     weapon2: weapon2}
  end

  describe "index" do
    test "lists weapons for a character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      weapon: weapon,
      weapon2: weapon2
    } do
      # Add weapons to character via Carry association
      add_weapon_to_character(character.id, weapon.id)
      add_weapon_to_character(character.id, weapon2.id)

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/weapons")
      response = json_response(conn, 200)

      assert response["meta"]["total"] == 2
      names = Enum.map(response["weapons"], & &1["name"])
      assert "Test Pistol" in names
      assert "Test Sword" in names
    end

    test "returns empty list when character has no weapons", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/weapons")
      response = json_response(conn, 200)

      assert response["weapons"] == []
      assert response["meta"]["total"] == 0
    end

    test "returns 404 for non-existent character", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/characters/#{non_existent_id}/weapons")
      assert json_response(conn, 404)
    end

    test "player can view their own character's weapons", %{
      conn: conn,
      player: player,
      character: character,
      weapon: weapon
    } do
      add_weapon_to_character(character.id, weapon.id)

      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/weapons")
      response = json_response(conn, 200)

      assert response["meta"]["total"] == 1
    end
  end

  describe "create" do
    test "adds weapon to character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      weapon: weapon
    } do
      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/weapons", weapon: %{id: weapon.id})

      response = json_response(conn, 200)
      assert weapon.id in response["weapon_ids"]
    end

    test "player can add weapon to their own character", %{
      conn: conn,
      player: player,
      character: character,
      weapon: weapon
    } do
      conn = authenticate(conn, player)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/weapons", weapon: %{id: weapon.id})

      response = json_response(conn, 200)
      assert weapon.id in response["weapon_ids"]
    end

    test "returns error when weapon already exists on character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      weapon: weapon
    } do
      # Add weapon first
      add_weapon_to_character(character.id, weapon.id)

      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/weapons", weapon: %{id: weapon.id})

      assert json_response(conn, 422)["error"] == "Character already has this weapon"
    end

    test "returns 404 for non-existent character", %{
      conn: conn,
      gamemaster: gm,
      weapon: weapon
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v2/characters/#{non_existent_id}/weapons", weapon: %{id: weapon.id})

      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent weapon", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/weapons", weapon: %{id: non_existent_id})

      assert json_response(conn, 404)
    end
  end

  describe "delete" do
    test "removes weapon from character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      weapon: weapon
    } do
      # Add weapon first
      add_weapon_to_character(character.id, weapon.id)

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/weapons/#{weapon.id}")
      assert response(conn, 204)

      # Verify weapon is removed
      updated_character = Characters.get_character(character.id)
      refute weapon.id in (updated_character.weapons |> Enum.map(& &1.id))
    end

    test "player can remove weapon from their own character", %{
      conn: conn,
      player: player,
      character: character,
      weapon: weapon
    } do
      # Add weapon first
      add_weapon_to_character(character.id, weapon.id)

      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/weapons/#{weapon.id}")
      assert response(conn, 204)
    end

    test "returns 404 when weapon not on character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      weapon: weapon
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/weapons/#{weapon.id}")
      assert json_response(conn, 404)["error"] == "Weapon not found on character"
    end

    test "returns 404 for non-existent character", %{
      conn: conn,
      gamemaster: gm,
      weapon: weapon
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/v2/characters/#{non_existent_id}/weapons/#{weapon.id}")
      assert json_response(conn, 404)
    end
  end

  describe "authorization" do
    test "non-member cannot access character weapons", %{
      conn: conn,
      other_user: other_user,
      character: character
    } do
      conn = authenticate(conn, other_user)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/weapons")
      assert json_response(conn, 404)
    end

    test "non-member cannot add weapon to character", %{
      conn: conn,
      other_user: other_user,
      character: character,
      weapon: weapon
    } do
      conn = authenticate(conn, other_user)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/weapons", weapon: %{id: weapon.id})

      assert json_response(conn, 404)
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp add_weapon_to_character(character_id, weapon_id) do
    alias ShotElixir.Weapons.Carry
    alias ShotElixir.Repo

    %Carry{}
    |> Ecto.Changeset.change(%{character_id: character_id, weapon_id: weapon_id})
    |> Repo.insert!()
  end
end
