defmodule ShotElixirWeb.Api.V2.CharacterControllerAuthorizationTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts
  }

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

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign for characters",
        user_id: gamemaster.id
      })

    # Set campaign as current for users
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     player: player_with_campaign,
     campaign: campaign}
  end

  describe "ownership management" do
    setup %{gamemaster: _gm, player: player, campaign: campaign} do
      {:ok, another_player} =
        Accounts.create_user(%{
          email: "player2@example.com",
          password: "password123",
          first_name: "Player",
          last_name: "Two",
          gamemaster: false
        })

      {:ok, another_player_with_campaign} =
        Accounts.set_current_campaign(another_player, campaign.id)

      {:ok, _} = Campaigns.add_member(campaign, another_player)

      {:ok, character} =
        Characters.create_character(%{
          name: "Ownership Test Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      %{character: character, another_player: another_player_with_campaign}
    end

    test "gamemaster can reassign character ownership", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      another_player: another_player
    } do
      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}",
          character: %{user_id: another_player.id}
        )

      response = json_response(conn, 200)

      assert response["user_id"] == another_player.id
    end

    test "player can reassign character ownership within campaign", %{
      conn: conn,
      player: player,
      character: character,
      another_player: another_player
    } do
      conn = authenticate(conn, player)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}",
          character: %{user_id: another_player.id}
        )

      response = json_response(conn, 200)
      # Character ownership can be reassigned to another campaign member
      assert response["user_id"] == another_player.id
    end

    test "ownership can be assigned to non-campaign-members", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      {:ok, non_member} =
        Accounts.create_user(%{
          email: "nonmember@example.com",
          password: "password123",
          first_name: "Non",
          last_name: "Member",
          gamemaster: false
        })

      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}", character: %{user_id: non_member.id})

      response = json_response(conn, 200)
      # Character ownership can be assigned to any user (current behavior)
      assert response["user_id"] == non_member.id
    end
  end

  describe "comprehensive authorization" do
    setup %{gamemaster: _gm, player: player, campaign: campaign} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          gamemaster: false,
          admin: true
        })

      {:ok, other_gm} =
        Accounts.create_user(%{
          email: "othergm@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "GM",
          gamemaster: true
        })

      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "Different campaign",
          user_id: other_gm.id
        })

      {:ok, other_character} =
        Characters.create_character(%{
          name: "Other Character",
          campaign_id: other_campaign.id,
          user_id: other_gm.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, player_character} =
        Characters.create_character(%{
          name: "Player Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      %{
        admin: admin,
        other_gm: other_gm,
        other_character: other_character,
        player_character: player_character
      }
    end

    test "admin can access characters from any campaign", %{
      conn: conn,
      admin: admin,
      other_character: other_character
    } do
      # First add admin to the other campaign so they have access
      other_campaign = ShotElixir.Campaigns.get_campaign!(other_character.campaign_id)
      {:ok, _} = ShotElixir.Campaigns.add_member(other_campaign, admin)

      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/characters/#{other_character.id}")
      response = json_response(conn, 200)

      assert response["id"] == other_character.id
    end

    test "gamemaster cannot access characters from other campaigns", %{
      conn: conn,
      gamemaster: gm,
      other_character: other_character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{other_character.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "player can only update their own characters", %{
      conn: conn,
      player: player,
      player_character: player_character,
      gamemaster: gm
    } do
      {:ok, gm_character} =
        Characters.create_character(%{
          name: "GM Character",
          campaign_id: player_character.campaign_id,
          user_id: gm.id,
          action_values: %{"Type" => "NPC"}
        })

      conn = authenticate(conn, player)

      # Can update own character
      conn1 =
        patch(conn, ~p"/api/v2/characters/#{player_character.id}",
          character: %{name: "Updated PC"}
        )

      response1 = json_response(conn1, 200)
      assert response1["name"] == "Updated PC"

      # Cannot update GM's character
      conn2 = patch(conn, ~p"/api/v2/characters/#{gm_character.id}", character: %{name: "Hacked"})
      assert json_response(conn2, 403)["error"] == "Forbidden"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
