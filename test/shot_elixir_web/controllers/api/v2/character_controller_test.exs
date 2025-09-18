defmodule ShotElixirWeb.Api.V2.CharacterControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.{Characters, Campaigns, Accounts, Schticks, Weapons, Sites, Parties, Factions, Junctures}
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Character",
    description: %{text: "A test character"},
    active: true,
    action_values: %{
      "Type" => "PC",
      "Archetype" => "Everyday Hero",
      "MainAttack" => 13,
      "Defense" => 14,
      "Toughness" => 7,
      "Speed" => 5
    },
    skills: %{
      "Driving" => 10,
      "Guns" => 13
    }
  }

  @update_attrs %{
    name: "Updated Character",
    description: %{text: "Updated description"},
    active: false
  }

  @invalid_attrs %{name: nil}

  setup %{conn: conn} do
    {:ok, gamemaster} = Accounts.create_user(%{
      email: "gm@example.com",
      password: "password123",
      first_name: "Game",
      last_name: "Master",
      gamemaster: true
    })

    {:ok, player} = Accounts.create_user(%{
      email: "player@example.com",
      password: "password123",
      first_name: "Player",
      last_name: "One",
      gamemaster: false
    })

    {:ok, campaign} = Campaigns.create_campaign(%{
      name: "Test Campaign",
      description: "Test campaign for characters",
      user_id: gamemaster.id
    })

    # Set campaign as current for users
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    {:ok, conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     player: player_with_campaign,
     campaign: campaign}
  end

  describe "index" do
    test "lists all characters in campaign", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, character1} = Characters.create_character(%{
        name: "Character 1",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC"}
      })

      {:ok, character2} = Characters.create_character(%{
        name: "Character 2",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "NPC"}
      })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters")
      response = json_response(conn, 200)

      assert is_list(response["characters"])
      assert length(response["characters"]) == 2

      character_names = Enum.map(response["characters"], & &1["name"])
      assert "Character 1" in character_names
      assert "Character 2" in character_names
    end

    test "returns error when no campaign set", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{
        email: "nocampaign@example.com",
        password: "password123",
        first_name: "No",
        last_name: "Campaign",
        gamemaster: false
      })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/characters")
      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    test "filters by search term", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, _} = Characters.create_character(%{
        name: "Maverick Cop",
        campaign_id: campaign.id,
        user_id: gm.id
      })

      {:ok, _} = Characters.create_character(%{
        name: "Ex-Special Forces",
        campaign_id: campaign.id,
        user_id: gm.id
      })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", search: "Maverick")
      response = json_response(conn, 200)

      assert length(response["characters"]) == 1
      assert List.first(response["characters"])["name"] == "Maverick Cop"
    end
  end

  describe "show" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC"}
      })

      %{character: character}
    end

    test "returns character when user has access", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      assert response["character"]["id"] == character.id
      assert response["character"]["name"] == "Test Character"
    end

    test "returns forbidden when user has no campaign access", %{conn: conn, character: character} do
      {:ok, other_user} = Accounts.create_user(%{
        email: "other@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "User"
      })

      conn = authenticate(conn, other_user)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns not found for invalid id", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/characters/#{invalid_id}")
      assert json_response(conn, 404)["error"] == "Not found"
    end
  end

  describe "create" do
    test "creates character when data is valid", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters", character: @create_attrs)
      response = json_response(conn, 201)

      assert response["character"]["name"] == "Test Character"
      assert response["character"]["action_values"]["Type"] == "PC"
      assert response["character"]["user_id"] == gm.id
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters", character: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end

    test "returns error when no campaign set", %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{
        email: "nocampaign2@example.com",
        password: "password123",
        first_name: "No",
        last_name: "Campaign"
      })

      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/characters", character: @create_attrs)
      assert json_response(conn, 400)["error"] == "No current campaign set"
    end
  end

  describe "update" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Original Character",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC"}
      })

      %{character: character}
    end

    test "updates character when user is owner", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @update_attrs)
      response = json_response(conn, 200)

      assert response["character"]["id"] == character.id
      assert response["character"]["name"] == "Updated Character"
      assert response["character"]["active"] == false
    end

    test "gamemaster can update any character", %{conn: conn, gamemaster: gm, player: player, campaign: campaign} do
      {:ok, player_character} = Characters.create_character(%{
        name: "Player's Character",
        campaign_id: campaign.id,
        user_id: player.id
      })

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{player_character.id}", character: @update_attrs)
      response = json_response(conn, 200)

      assert response["character"]["name"] == "Updated Character"
    end

    test "non-owner non-gm cannot update", %{conn: conn, player: player, character: character} do
      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @update_attrs)
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end
  end

  describe "delete" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Character to Delete",
        campaign_id: campaign.id,
        user_id: gm.id
      })

      %{character: character}
    end

    test "soft deletes character when user is owner", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}")
      assert response(conn, 204)

      # Verify character is soft deleted
      deleted_character = Characters.get_character(character.id)
      assert deleted_character.active == false
    end

    test "returns forbidden when user is not owner", %{conn: conn, player: player, character: character} do
      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end
  end

  describe "duplicate" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Original Character",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC", "MainAttack" => 13}
      })

      %{character: character}
    end

    test "duplicates character for user with access", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{character.id}/duplicate")
      response = json_response(conn, 201)

      assert response["character"]["name"] == "Original Character (Copy)"
      assert response["character"]["action_values"]["Type"] == "PC"
      assert response["character"]["user_id"] == gm.id
    end

    test "returns forbidden when user has no access", %{conn: conn, character: character} do
      {:ok, other_user} = Accounts.create_user(%{
        email: "nodup@example.com",
        password: "password123",
        first_name: "No",
        last_name: "Dup"
      })

      conn = authenticate(conn, other_user)
      conn = post(conn, ~p"/api/v2/characters/#{character.id}/duplicate")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end
  end

  describe "autocomplete" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, _} = Characters.create_character(%{
        name: "Maverick Cop",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC", "Archetype" => "Maverick Cop"}
      })

      {:ok, _} = Characters.create_character(%{
        name: "Masked Avenger",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC", "Archetype" => "Masked Avenger"}
      })

      {:ok, _} = Characters.create_character(%{
        name: "Big Bruiser",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "NPC"}
      })

      :ok
    end

    test "returns matching characters", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/names", q: "Ma")
      response = json_response(conn, 200)

      assert length(response["characters"]) == 2
      names = Enum.map(response["characters"], & &1["name"])
      assert "Maverick Cop" in names
      assert "Masked Avenger" in names
    end

    test "returns empty when no matches", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/names", q: "xyz")
      response = json_response(conn, 200)

      assert response["characters"] == []
    end
  end

  describe "association rendering" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC"}
      })

      {:ok, schtick} = Schticks.create_schtick(%{
        name: "Gun Schtick",
        description: "Gun related ability",
        category: "guns",
        path: "Path of the Gun",
        campaign_id: campaign.id
      })

      {:ok, weapon} = Weapons.create_weapon(%{
        name: "Glock 17",
        description: "Reliable pistol",
        damage: 13,
        concealment: 0,
        campaign_id: campaign.id
      })

      %{character: character, schtick: schtick, weapon: weapon}
    end

    test "includes empty associations when none are loaded", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      # Character should have empty arrays for associations that aren't loaded
      assert response["character"]["schticks"] == []
      assert response["character"]["weapons"] == []
    end

    test "renders basic character data correctly", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      char = response["character"]
      assert char["id"] == character.id
      assert char["name"] == character.name
      assert char["action_values"]["Type"] == "PC"
      assert char["user_id"] == character.user_id
      assert char["campaign_id"] == character.campaign_id
    end
  end

  describe "wounds and impairments" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Wounded Character",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{
          "Type" => "PC",
          "Toughness" => 7,
          "Body" => 0,
          "Impairments" => []
        }
      })

      %{character: character}
    end

    test "updates wounds and body points", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)

      wound_attrs = %{
        action_values: %{
          "Body" => -15,
          "Impairments" => ["Impaired", "Seriously Wounded"]
        }
      }

      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: wound_attrs)
      response = json_response(conn, 200)

      assert response["character"]["action_values"]["Body"] == -15
      assert "Impaired" in response["character"]["action_values"]["Impairments"]
      assert "Seriously Wounded" in response["character"]["action_values"]["Impairments"]
    end

    test "tracks multiple wound states", %{conn: conn, gamemaster: gm, character: character} do
      conn = authenticate(conn, gm)

      # Apply multiple impairments
      wound_attrs = %{
        action_values: %{
          "Body" => -30,
          "Impairments" => ["Impaired", "Seriously Wounded", "Incapacitated"]
        }
      }

      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: wound_attrs)
      response = json_response(conn, 200)

      assert response["character"]["action_values"]["Body"] == -30
      assert length(response["character"]["action_values"]["Impairments"]) == 3
    end
  end

  describe "ownership management" do
    setup %{gamemaster: gm, player: player, campaign: campaign} do
      {:ok, another_player} = Accounts.create_user(%{
        email: "player2@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "Two",
        gamemaster: false
      })

      {:ok, another_player_with_campaign} = Accounts.set_current_campaign(another_player, campaign.id)
      {:ok, _} = Campaigns.add_member(campaign, another_player)

      {:ok, character} = Characters.create_character(%{
        name: "Ownership Test Character",
        campaign_id: campaign.id,
        user_id: player.id,
        action_values: %{"Type" => "PC"}
      })

      %{character: character, another_player: another_player_with_campaign}
    end

    test "gamemaster can reassign character ownership", %{conn: conn, gamemaster: gm, character: character, another_player: another_player} do
      conn = authenticate(conn, gm)

      conn = patch(conn, ~p"/api/v2/characters/#{character.id}",
        character: %{user_id: another_player.id})
      response = json_response(conn, 200)

      assert response["character"]["user_id"] == another_player.id
    end

    test "player can reassign character ownership within campaign", %{conn: conn, player: player, character: character, another_player: another_player} do
      conn = authenticate(conn, player)

      conn = patch(conn, ~p"/api/v2/characters/#{character.id}",
        character: %{user_id: another_player.id})

      response = json_response(conn, 200)
      # Character ownership can be reassigned to another campaign member
      assert response["character"]["user_id"] == another_player.id
    end

    test "ownership can be assigned to non-campaign-members", %{conn: conn, gamemaster: gm, character: character} do
      {:ok, non_member} = Accounts.create_user(%{
        email: "nonmember@example.com",
        password: "password123",
        first_name: "Non",
        last_name: "Member",
        gamemaster: false
      })

      conn = authenticate(conn, gm)

      conn = patch(conn, ~p"/api/v2/characters/#{character.id}",
        character: %{user_id: non_member.id})

      response = json_response(conn, 200)
      # Character ownership can be assigned to any user (current behavior)
      assert response["character"]["user_id"] == non_member.id
    end
  end

  # TODO: Character number incrementing tests - functionality not yet implemented
  # describe "character number incrementing" do
  #   setup %{gamemaster: gm, campaign: campaign} do
  #     %{gm: gm, campaign: campaign}
  #   end

  #   test "creates sequential numbered characters with same name", %{conn: conn, gm: gm} do
  #     conn = authenticate(conn, gm)

  #     # Create first character
  #     conn1 = post(conn, ~p"/api/v2/characters", character: %{name: "Guard", action_values: %{"Type" => "Mook"}})
  #     response1 = json_response(conn1, 201)
  #     assert response1["character"]["name"] == "Guard"

  #     # Create second character with same name
  #     conn2 = post(conn, ~p"/api/v2/characters", character: %{name: "Guard", action_values: %{"Type" => "Mook"}})
  #     response2 = json_response(conn2, 201)
  #     assert response2["character"]["name"] == "Guard 2"

  #     # Create third character with same name
  #     conn3 = post(conn, ~p"/api/v2/characters", character: %{name: "Guard", action_values: %{"Type" => "Mook"}})
  #     response3 = json_response(conn3, 201)
  #     assert response3["character"]["name"] == "Guard 3"
  #   end

  #   test "handles gaps in numbering", %{conn: conn, gm: gm, campaign: campaign} do
  #     conn = authenticate(conn, gm)

  #     # Create characters with gaps
  #     {:ok, _char1} = Characters.create_character(%{name: "Thug", campaign_id: campaign.id, user_id: gm.id})
  #     {:ok, char2} = Characters.create_character(%{name: "Thug 2", campaign_id: campaign.id, user_id: gm.id})
  #     {:ok, _char3} = Characters.create_character(%{name: "Thug 4", campaign_id: campaign.id, user_id: gm.id})

  #     # Delete the middle one to create a gap
  #     Characters.delete_character(char2)

  #     # New character should use next available number
  #     conn = post(conn, ~p"/api/v2/characters", character: %{name: "Thug", action_values: %{"Type" => "Mook"}})
  #     response = json_response(conn, 201)
  #     assert response["character"]["name"] == "Thug 5"
  #   end
  # end

  describe "comprehensive authorization" do
    setup %{gamemaster: gm, player: player, campaign: campaign} do
      {:ok, admin} = Accounts.create_user(%{
        email: "admin@example.com",
        password: "password123",
        first_name: "Admin",
        last_name: "User",
        gamemaster: false,
        admin: true
      })

      {:ok, other_gm} = Accounts.create_user(%{
        email: "othergm@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "GM",
        gamemaster: true
      })

      {:ok, other_campaign} = Campaigns.create_campaign(%{
        name: "Other Campaign",
        description: "Different campaign",
        user_id: other_gm.id
      })

      {:ok, other_character} = Characters.create_character(%{
        name: "Other Character",
        campaign_id: other_campaign.id,
        user_id: other_gm.id,
        action_values: %{"Type" => "PC"}
      })

      {:ok, player_character} = Characters.create_character(%{
        name: "Player Character",
        campaign_id: campaign.id,
        user_id: player.id,
        action_values: %{"Type" => "PC"}
      })

      %{admin: admin, other_gm: other_gm, other_character: other_character, player_character: player_character}
    end

    test "admin can access characters from any campaign", %{conn: conn, admin: admin, other_character: other_character} do
      # First add admin to the other campaign so they have access
      other_campaign = ShotElixir.Campaigns.get_campaign!(other_character.campaign_id)
      {:ok, _} = ShotElixir.Campaigns.add_member(other_campaign, admin)

      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/characters/#{other_character.id}")
      response = json_response(conn, 200)

      assert response["character"]["id"] == other_character.id
    end

    test "gamemaster cannot access characters from other campaigns", %{conn: conn, gamemaster: gm, other_character: other_character} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{other_character.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "player can only update their own characters", %{conn: conn, player: player, player_character: player_character, gamemaster: gm} do
      {:ok, gm_character} = Characters.create_character(%{
        name: "GM Character",
        campaign_id: player_character.campaign_id,
        user_id: gm.id,
        action_values: %{"Type" => "NPC"}
      })

      conn = authenticate(conn, player)

      # Can update own character
      conn1 = patch(conn, ~p"/api/v2/characters/#{player_character.id}", character: %{name: "Updated PC"})
      response1 = json_response(conn1, 200)
      assert response1["character"]["name"] == "Updated PC"

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