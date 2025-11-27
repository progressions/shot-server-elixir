defmodule ShotElixirWeb.Api.V2.CharacterSchtickControllerTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.{Characters, Campaigns, Accounts, Schticks}
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
        description: "Test campaign for character schticks",
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

    {:ok, schtick} =
      Schticks.create_schtick(%{
        name: "Test Schtick",
        description: "A test schtick",
        campaign_id: campaign.id,
        category: "Gun"
      })

    {:ok, schtick2} =
      Schticks.create_schtick(%{
        name: "Second Schtick",
        description: "Another schtick",
        campaign_id: campaign.id,
        category: "Martial Arts"
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gamemaster,
     player: player,
     other_user: other_user,
     campaign: campaign,
     character: character,
     schtick: schtick,
     schtick2: schtick2}
  end

  describe "index" do
    test "lists schticks for a character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      schtick: schtick,
      schtick2: schtick2
    } do
      # Add schticks to character
      Characters.update_character(character, %{schtick_ids: [schtick.id, schtick2.id]})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/schticks")
      response = json_response(conn, 200)

      assert response["meta"]["total"] == 2
      names = Enum.map(response["schticks"], & &1["name"])
      assert "Test Schtick" in names
      assert "Second Schtick" in names
    end

    test "returns empty list when character has no schticks", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/schticks")
      response = json_response(conn, 200)

      assert response["schticks"] == []
      assert response["meta"]["total"] == 0
    end

    test "returns 404 for non-existent character", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/characters/#{non_existent_id}/schticks")
      assert json_response(conn, 404)
    end

    test "player can view their own character's schticks", %{
      conn: conn,
      player: player,
      character: character,
      schtick: schtick
    } do
      Characters.update_character(character, %{schtick_ids: [schtick.id]})

      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/schticks")
      response = json_response(conn, 200)

      assert response["meta"]["total"] == 1
    end
  end

  describe "create" do
    test "adds schtick to character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      schtick: schtick
    } do
      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/schticks", schtick: %{id: schtick.id})

      response = json_response(conn, 200)
      assert schtick.id in response["schtick_ids"]
    end

    test "player can add schtick to their own character", %{
      conn: conn,
      player: player,
      character: character,
      schtick: schtick
    } do
      conn = authenticate(conn, player)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/schticks", schtick: %{id: schtick.id})

      response = json_response(conn, 200)
      assert schtick.id in response["schtick_ids"]
    end

    test "returns error when schtick already exists on character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      schtick: schtick
    } do
      # Add schtick first
      Characters.update_character(character, %{schtick_ids: [schtick.id]})

      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/schticks", schtick: %{id: schtick.id})

      assert json_response(conn, 422)["error"] == "Character already has this schtick"
    end

    test "returns 404 for non-existent character", %{
      conn: conn,
      gamemaster: gm,
      schtick: schtick
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v2/characters/#{non_existent_id}/schticks", schtick: %{id: schtick.id})

      assert json_response(conn, 404)
    end

    test "returns 404 for non-existent schtick", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/schticks",
          schtick: %{id: non_existent_id}
        )

      assert json_response(conn, 404)
    end
  end

  describe "delete" do
    test "removes schtick from character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      schtick: schtick
    } do
      # Add schtick first
      Characters.update_character(character, %{schtick_ids: [schtick.id]})

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/schticks/#{schtick.id}")
      assert response(conn, 204)

      # Verify schtick is removed
      updated_character = Characters.get_character(character.id)
      refute schtick.id in (updated_character.schticks |> Enum.map(& &1.id))
    end

    test "player can remove schtick from their own character", %{
      conn: conn,
      player: player,
      character: character,
      schtick: schtick
    } do
      # Add schtick first
      Characters.update_character(character, %{schtick_ids: [schtick.id]})

      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/schticks/#{schtick.id}")
      assert response(conn, 204)
    end

    test "returns 404 when schtick not on character", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      schtick: schtick
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/schticks/#{schtick.id}")
      assert json_response(conn, 404)["error"] == "Schtick not found on character"
    end

    test "returns 404 for non-existent character", %{
      conn: conn,
      gamemaster: gm,
      schtick: schtick
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/v2/characters/#{non_existent_id}/schticks/#{schtick.id}")
      assert json_response(conn, 404)
    end
  end

  describe "authorization" do
    test "non-member cannot access character schticks", %{
      conn: conn,
      other_user: other_user,
      character: character
    } do
      conn = authenticate(conn, other_user)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/schticks")
      assert json_response(conn, 404)
    end

    test "non-member cannot add schtick to character", %{
      conn: conn,
      other_user: other_user,
      character: character,
      schtick: schtick
    } do
      conn = authenticate(conn, other_user)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/schticks", schtick: %{id: schtick.id})

      assert json_response(conn, 404)
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
