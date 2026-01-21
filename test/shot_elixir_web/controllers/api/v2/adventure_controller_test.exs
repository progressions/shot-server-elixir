defmodule ShotElixirWeb.Api.V2.AdventureControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Adventures, Characters, Fights, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm_adventure@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Adventure Test Campaign",
        description: "Campaign for adventure testing",
        user_id: gamemaster.id
      })

    # Set current campaign for gamemaster
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> authenticate(gamemaster)

    %{
      conn: conn,
      user: gamemaster,
      campaign: campaign
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all adventures for campaign", %{conn: conn, campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Chicago On Fire",
          campaign_id: campaign.id,
          user_id: user.id,
          description: "A blazing adventure"
        })

      conn = get(conn, ~p"/api/v2/adventures")
      assert %{"adventures" => [returned_adventure]} = json_response(conn, 200)
      assert returned_adventure["id"] == adventure.id
      assert returned_adventure["name"] == "Chicago On Fire"
    end

    test "returns empty list when no adventures", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/adventures")
      assert %{"adventures" => []} = json_response(conn, 200)
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      {:ok, user_without_campaign} = Accounts.update_user(user, %{current_campaign_id: nil})

      conn =
        conn
        |> authenticate(user_without_campaign)
        |> get(~p"/api/v2/adventures")

      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end
  end

  describe "show" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Chicago On Fire",
          campaign_id: campaign.id,
          user_id: user.id,
          description: "A blazing adventure"
        })

      %{adventure: adventure}
    end

    test "returns adventure when found", %{conn: conn, adventure: adventure} do
      conn = get(conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert returned_adventure = json_response(conn, 200)
      assert returned_adventure["id"] == adventure.id
      assert returned_adventure["name"] == "Chicago On Fire"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/adventures/#{Ecto.UUID.generate()}")
      assert %{"error" => "Adventure not found"} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "creates adventure with valid data", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/adventures", %{
          adventure: %{
            name: "New Adventure",
            description: "A new adventure",
            season: 1
          }
        })

      assert adventure = json_response(conn, 201)
      assert adventure["name"] == "New Adventure"
      assert adventure["description"] == "A new adventure"
      assert adventure["season"] == 1
    end

    test "returns errors with invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/adventures", %{
          adventure: %{
            description: "Missing name"
          }
        })

      assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
    end
  end

  describe "update" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Original Name",
          campaign_id: campaign.id,
          user_id: user.id
        })

      %{adventure: adventure}
    end

    test "updates adventure with valid data", %{conn: conn, adventure: adventure} do
      conn =
        patch(conn, ~p"/api/v2/adventures/#{adventure.id}", %{
          adventure: %{
            name: "Updated Name",
            description: "Updated description"
          }
        })

      assert updated = json_response(conn, 200)
      assert updated["name"] == "Updated Name"
      assert updated["description"] == "Updated description"
    end
  end

  describe "delete" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure to Delete",
          campaign_id: campaign.id,
          user_id: user.id
        })

      %{adventure: adventure}
    end

    test "deletes adventure", %{conn: conn, adventure: adventure} do
      conn = delete(conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert response(conn, 204)

      conn = get(conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert json_response(conn, 404)
    end
  end

  describe "add_character" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Hero",
          campaign_id: campaign.id
        })

      %{adventure: adventure, character: character}
    end

    test "adds character as hero to adventure", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        post(conn, ~p"/api/v2/adventures/#{adventure.id}/characters", %{
          character_id: character.id
        })

      assert updated = json_response(conn, 200)
      assert character.id in updated["character_ids"]
    end
  end

  describe "remove_character" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Hero",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_character(adventure, character.id)

      %{adventure: adventure, character: character}
    end

    test "removes character from adventure heroes", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        delete(conn, ~p"/api/v2/adventures/#{adventure.id}/characters/#{character.id}")

      assert updated = json_response(conn, 200)
      refute character.id in updated["character_ids"]
    end
  end

  describe "add_villain" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Villain",
          campaign_id: campaign.id
        })

      %{adventure: adventure, character: character}
    end

    test "adds character as villain to adventure", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        post(conn, ~p"/api/v2/adventures/#{adventure.id}/villains", %{
          character_id: character.id
        })

      assert updated = json_response(conn, 200)
      assert character.id in updated["villain_ids"]
    end
  end

  describe "remove_villain" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Villain",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_villain(adventure, character.id)

      %{adventure: adventure, character: character}
    end

    test "removes villain from adventure", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        delete(conn, ~p"/api/v2/adventures/#{adventure.id}/villains/#{character.id}")

      assert updated = json_response(conn, 200)
      refute character.id in updated["villain_ids"]
    end

    test "returns 404 when villain not in adventure", %{conn: conn, adventure: adventure} do
      non_existent_id = Ecto.UUID.generate()

      conn =
        delete(conn, ~p"/api/v2/adventures/#{adventure.id}/villains/#{non_existent_id}")

      assert %{"error" => "Villain not in adventure"} = json_response(conn, 404)
    end
  end

  describe "add_fight" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      %{adventure: adventure, fight: fight}
    end

    test "adds fight to adventure", %{
      conn: conn,
      adventure: adventure,
      fight: fight
    } do
      conn =
        post(conn, ~p"/api/v2/adventures/#{adventure.id}/fights", %{
          fight_id: fight.id
        })

      assert updated = json_response(conn, 200)
      assert fight.id in updated["fight_ids"]
    end
  end

  describe "remove_fight" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_fight(adventure, fight.id)

      %{adventure: adventure, fight: fight}
    end

    test "removes fight from adventure", %{
      conn: conn,
      adventure: adventure,
      fight: fight
    } do
      conn =
        delete(conn, ~p"/api/v2/adventures/#{adventure.id}/fights/#{fight.id}")

      assert updated = json_response(conn, 200)
      refute fight.id in updated["fight_ids"]
    end

    test "returns 404 when fight not in adventure", %{conn: conn, adventure: adventure} do
      non_existent_id = Ecto.UUID.generate()

      conn =
        delete(conn, ~p"/api/v2/adventures/#{adventure.id}/fights/#{non_existent_id}")

      assert %{"error" => "Fight not in adventure"} = json_response(conn, 404)
    end
  end

  describe "player access restrictions" do
    setup %{conn: conn, campaign: campaign, user: gamemaster} do
      # Create a player user (not gamemaster, not admin)
      {:ok, player} =
        Accounts.create_user(%{
          email: "player_adventure@test.com",
          password: "password123",
          first_name: "Player",
          last_name: "User",
          gamemaster: false,
          admin: false
        })

      # Add player as campaign member
      {:ok, _membership} = Campaigns.add_member(campaign, player)

      # Set current campaign for player
      {:ok, player} = Accounts.update_user(player, %{current_campaign_id: campaign.id})

      # Create an adventure
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          description: "Adventure description",
          rich_description: "<p>Rich description with secrets</p>",
          campaign_id: campaign.id,
          user_id: gamemaster.id,
          season: 1
        })

      # Create a character owned by the player
      {:ok, player_character} =
        Characters.create_character(%{
          name: "Player's Hero",
          campaign_id: campaign.id,
          user_id: player.id
        })

      # Create a character owned by the gamemaster (NPC)
      {:ok, gm_character} =
        Characters.create_character(%{
          name: "GM's NPC",
          campaign_id: campaign.id,
          user_id: gamemaster.id
        })

      # Create a villain character
      {:ok, villain} =
        Characters.create_character(%{
          name: "Big Bad Boss",
          campaign_id: campaign.id,
          user_id: gamemaster.id
        })

      # Add characters to adventure
      {:ok, adventure} = Adventures.add_character(adventure, player_character.id)
      {:ok, adventure} = Adventures.add_character(adventure, gm_character.id)
      {:ok, adventure} = Adventures.add_villain(adventure, villain.id)

      player_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> authenticate(player)

      %{
        player: player,
        player_conn: player_conn,
        adventure: adventure,
        player_character: player_character,
        gm_character: gm_character,
        villain: villain
      }
    end

    test "player receives 403 when listing adventures", %{player_conn: conn} do
      conn = get(conn, ~p"/api/v2/adventures")
      assert %{"error" => "Players cannot list adventures"} = json_response(conn, 403)
    end

    test "gamemaster can still list adventures", %{conn: gm_conn, adventure: adventure} do
      conn = get(gm_conn, ~p"/api/v2/adventures")
      assert %{"adventures" => adventures} = json_response(conn, 200)
      assert length(adventures) >= 1
      assert Enum.any?(adventures, fn a -> a["id"] == adventure.id end)
    end

    test "player receives restricted data when viewing adventure", %{
      player_conn: conn,
      adventure: adventure,
      player_character: player_character,
      gm_character: gm_character
    } do
      conn = get(conn, ~p"/api/v2/adventures/#{adventure.id}")
      response = json_response(conn, 200)

      # Should have restricted_view flag
      assert response["restricted_view"] == true

      # Should have basic fields
      assert response["id"] == adventure.id
      assert response["name"] == "Test Adventure"
      assert response["description"] == "Adventure description"
      assert response["season"] == 1

      # Should NOT have rich_description (sensitive GM content)
      refute Map.has_key?(response, "rich_description")

      # Should NOT have mentions
      refute Map.has_key?(response, "mentions")

      # Characters should only include player's own character
      character_ids = response["character_ids"]
      assert player_character.id in character_ids
      refute gm_character.id in character_ids

      # Villains should be empty for players
      assert response["villain_ids"] == []
      assert response["villains"] == []

      # Fights should be empty for players
      assert response["fight_ids"] == []
      assert response["fights"] == []
    end

    test "gamemaster receives full data when viewing adventure", %{
      conn: gm_conn,
      adventure: adventure,
      player_character: player_character,
      gm_character: gm_character,
      villain: villain
    } do
      conn = get(gm_conn, ~p"/api/v2/adventures/#{adventure.id}")
      response = json_response(conn, 200)

      # Should NOT have restricted_view flag
      refute response["restricted_view"]

      # Should have all fields
      assert response["id"] == adventure.id
      assert response["name"] == "Test Adventure"
      assert response["rich_description"] == "<p>Rich description with secrets</p>"

      # Should have all characters
      character_ids = response["character_ids"]
      assert player_character.id in character_ids
      assert gm_character.id in character_ids

      # Should have villains
      assert villain.id in response["villain_ids"]
    end

    test "non-member user cannot access adventures at all", %{conn: conn, adventure: adventure} do
      # Create a user who is not a member of this campaign
      {:ok, non_member} =
        Accounts.create_user(%{
          email: "non_member@test.com",
          password: "password123",
          first_name: "Non",
          last_name: "Member",
          gamemaster: false
        })

      # Create a different campaign and set it as current
      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          user_id: non_member.id
        })

      {:ok, non_member} =
        Accounts.update_user(non_member, %{current_campaign_id: other_campaign.id})

      non_member_conn =
        conn
        |> put_req_header("accept", "application/json")
        |> authenticate(non_member)

      # Non-member trying to view adventure from different campaign should get 404
      conn = get(non_member_conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert %{"error" => "Adventure not found"} = json_response(conn, 404)
    end
  end
end
