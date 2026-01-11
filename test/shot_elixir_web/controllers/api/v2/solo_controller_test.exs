defmodule ShotElixirWeb.Api.V2.SoloControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Fights, Campaigns, Accounts, Characters, Repo}
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm_#{System.unique_integer()}@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create player user (campaign member)
    {:ok, player} =
      Accounts.create_user(%{
        email: "player_#{System.unique_integer()}@test.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create non-member user
    {:ok, non_member} =
      Accounts.create_user(%{
        email: "nonmember_#{System.unique_integer()}@test.com",
        password: "password123",
        first_name: "Non",
        last_name: "Member",
        gamemaster: false
      })

    # Create a campaign directly using Repo.insert! to bypass CampaignSeederWorker
    campaign =
      %Campaign{}
      |> Ecto.Changeset.change(%{
        name: "Test Campaign",
        description: "Campaign for solo testing",
        user_id: gamemaster.id
      })
      |> Repo.insert!()

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    # Create a solo mode fight
    {:ok, solo_fight} =
      Fights.create_fight(%{
        name: "Solo Test Fight",
        description: "A test fight in solo mode",
        campaign_id: campaign.id,
        active: true,
        solo_mode: true,
        solo_behavior_type: "simple"
      })

    # Create a regular (non-solo) fight
    {:ok, regular_fight} =
      Fights.create_fight(%{
        name: "Regular Fight",
        description: "A regular fight",
        campaign_id: campaign.id,
        active: true,
        solo_mode: false
      })

    # Create PC character
    {:ok, pc_character} =
      Characters.create_character(%{
        name: "Test PC",
        character_type: :pc,
        campaign_id: campaign.id,
        action_values: %{"Guns" => 13, "Defense" => 13, "Speed" => 7, "Toughness" => 6}
      })

    # Create NPC character
    {:ok, npc_character} =
      Characters.create_character(%{
        name: "Test NPC",
        character_type: :featured_foe,
        campaign_id: campaign.id,
        action_values: %{
          "Guns" => 12,
          "Defense" => 12,
          "Speed" => 6,
          "Toughness" => 5,
          "Damage" => 8
        }
      })

    # Add characters to solo fight as shots
    {:ok, _pc_shot} =
      Fights.create_shot(%{
        fight_id: solo_fight.id,
        character_id: pc_character.id,
        shot: 0
      })

    {:ok, _npc_shot} =
      Fights.create_shot(%{
        fight_id: solo_fight.id,
        character_id: npc_character.id,
        shot: 0
      })

    # Update solo fight with PC character IDs
    {:ok, solo_fight} =
      Fights.update_fight(solo_fight, %{
        solo_player_character_ids: [pc_character.id]
      })

    conn = put_req_header(conn, "accept", "application/json")

    %{
      conn: conn,
      gamemaster: gamemaster,
      player: player,
      non_member: non_member,
      campaign: campaign,
      solo_fight: solo_fight,
      regular_fight: regular_fight,
      pc_character: pc_character,
      npc_character: npc_character
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "status" do
    test "returns status for campaign owner", %{
      conn: conn,
      gamemaster: gm,
      solo_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/solo/status")
      response = json_response(conn, 200)

      assert response["fight_id"] == fight.id
      assert response["running"] == false
    end

    test "returns status for campaign member", %{
      conn: conn,
      player: player,
      solo_fight: fight
    } do
      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/solo/status")
      response = json_response(conn, 200)

      assert response["fight_id"] == fight.id
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      solo_fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/solo/status")

      assert json_response(conn, 403)["error"] =~ "Not authorized"
    end

    test "returns not found for non-existent fight", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      fake_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/fights/#{fake_id}/solo/status")

      # Controller returns 404 with "Fight not found" error for non-existent fights
      response = json_response(conn, 404)
      assert response["success"] == false
      assert response["error"] =~ "Fight not found"
    end
  end

  describe "start - authorization" do
    test "returns error for non-solo fight", %{
      conn: conn,
      gamemaster: gm,
      regular_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/start")
      response = json_response(conn, 422)

      assert response["success"] == false
      assert response["error"] =~ "solo mode"
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      solo_fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/start")

      assert json_response(conn, 403)["error"] =~ "Not authorized"
    end
  end

  describe "roll_initiative" do
    test "returns error for non-solo fight", %{
      conn: conn,
      gamemaster: gm,
      regular_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/roll_initiative")
      response = json_response(conn, 422)

      assert response["success"] == false
      assert response["error"] =~ "solo mode"
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      solo_fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/roll_initiative")

      assert json_response(conn, 403)["error"] =~ "Not authorized"
    end

    test "rolls initiative for all combatants", %{
      conn: conn,
      gamemaster: gm,
      solo_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/roll_initiative")
      response = json_response(conn, 200)

      assert response["success"] == true
      assert is_list(response["results"])
      assert length(response["results"]) == 2

      Enum.each(response["results"], fn result ->
        assert is_binary(result["name"])
        assert is_integer(result["roll"])
        assert is_integer(result["speed"])
        assert is_integer(result["shot"])
      end)
    end
  end

  describe "player_action" do
    test "executes attack action", %{
      conn: conn,
      gamemaster: gm,
      solo_fight: fight,
      pc_character: pc,
      npc_character: npc
    } do
      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/solo/action", %{
          "action_type" => "attack",
          "character_id" => pc.id,
          "target_id" => npc.id
        })

      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["action"]["action_type"] == "attack"
      assert response["action"]["actor_name"] == "Test PC"
      assert response["action"]["target_name"] == "Test NPC"
      assert is_binary(response["action"]["narrative"])
      assert is_boolean(response["action"]["hit"])
    end

    test "executes defend action", %{
      conn: conn,
      gamemaster: gm,
      solo_fight: fight,
      pc_character: pc,
      npc_character: npc
    } do
      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/solo/action", %{
          "action_type" => "defend",
          "character_id" => pc.id,
          "target_id" => npc.id
        })

      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["action"]["action_type"] == "defend"
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      solo_fight: fight,
      pc_character: pc,
      npc_character: npc
    } do
      conn = authenticate(conn, non_member)

      conn =
        post(conn, ~p"/api/v2/fights/#{fight.id}/solo/action", %{
          "action_type" => "attack",
          "character_id" => pc.id,
          "target_id" => npc.id
        })

      assert json_response(conn, 403)["error"] =~ "Not authorized"
    end
  end

  describe "stop - authorization" do
    test "returns success for campaign owner", %{
      conn: conn,
      gamemaster: gm,
      solo_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/stop")
      response = json_response(conn, 200)

      assert response["success"] == true
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      solo_fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/stop")

      assert json_response(conn, 403)["error"] =~ "Not authorized"
    end
  end

  describe "advance - authorization" do
    test "returns error when server not running", %{
      conn: conn,
      gamemaster: gm,
      solo_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/advance")
      response = json_response(conn, 422)

      assert response["success"] == false
      assert response["error"] =~ "not running"
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      solo_fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/solo/advance")

      assert json_response(conn, 403)["error"] =~ "Not authorized"
    end
  end
end
