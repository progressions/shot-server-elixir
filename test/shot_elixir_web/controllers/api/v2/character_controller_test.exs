defmodule ShotElixirWeb.Api.V2.CharacterControllerTest do
  @moduledoc """
  Core CRUD tests for the Character controller.

  Additional tests are split into:
  - character_controller_filtering_test.exs - Index filtering and sorting
  - character_controller_authorization_test.exs - Authorization and ownership
  - character_controller_features_test.exs - Association rendering, wounds, impairments
  """
  use ShotElixirWeb.ConnCase, async: false

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts
  }

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

  describe "index" do
    test "lists all characters in campaign", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, character1} =
        Characters.create_character(%{
          name: "Character 1",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, character2} =
        Characters.create_character(%{
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
      {:ok, user} =
        Accounts.create_user(%{
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
      {:ok, _} =
        Characters.create_character(%{
          name: "Maverick Cop XYZ123",
          campaign_id: campaign.id,
          user_id: gm.id,
          is_template: false
        })

      {:ok, _} =
        Characters.create_character(%{
          name: "Ex-Special Forces",
          campaign_id: campaign.id,
          user_id: gm.id,
          is_template: false
        })

      conn = authenticate(conn, gm)
      # Explicitly exclude templates to ensure test isolation
      conn = get(conn, ~p"/api/v2/characters", search: "XYZ123", template_filter: "false")
      response = json_response(conn, 200)

      assert length(response["characters"]) == 1
      assert List.first(response["characters"])["name"] == "Maverick Cop XYZ123"
    end
  end

  describe "show" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC"}
        })

      %{character: character}
    end

    test "returns character when user has access", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      assert response["id"] == character.id
      assert response["name"] == "Test Character"
    end

    test "returns forbidden when user has no campaign access", %{conn: conn, character: character} do
      {:ok, other_user} =
        Accounts.create_user(%{
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

      assert response["name"] == "Test Character"
      assert response["action_values"]["Type"] == "PC"
      assert response["user_id"] == gm.id
    end

    test "broadcasts character creation via WebSocket", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters", character: @create_attrs)
      response = json_response(conn, 201)

      # Verify character was created
      assert response["id"]
      assert response["name"] == "Test Character"
      # TODO: Add proper WebSocket testing once Phoenix Channel test infrastructure is complete
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters", character: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end

    test "returns error when no campaign set", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
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
      {:ok, character} =
        Characters.create_character(%{
          name: "Original Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC"}
        })

      %{character: character}
    end

    test "updates character when user is owner", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @update_attrs)
      response = json_response(conn, 200)

      assert response["id"] == character.id
      assert response["name"] == "Updated Character"
      assert response["active"] == false
    end

    test "broadcasts character update via WebSocket", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      campaign: campaign
    } do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @update_attrs)
      response = json_response(conn, 200)

      # Verify update was successful
      assert response["name"] == "Updated Character"
      # TODO: Add proper WebSocket testing once Phoenix Channel test infrastructure is complete
    end

    test "gamemaster can update any character", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      {:ok, player_character} =
        Characters.create_character(%{
          name: "Player's Character",
          campaign_id: campaign.id,
          user_id: player.id
        })

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{player_character.id}", character: @update_attrs)
      response = json_response(conn, 200)

      assert response["name"] == "Updated Character"
    end

    test "non-owner non-gm cannot update", %{conn: conn, player: player, character: character} do
      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @update_attrs)
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "renders errors when data is invalid", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/characters/#{character.id}", character: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end
  end

  describe "delete" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Character to Delete",
          campaign_id: campaign.id,
          user_id: gm.id
        })

      %{character: character}
    end

    test "deletes character when user is owner", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}")
      assert response(conn, 204)

      # Verify character is actually deleted from database
      assert Characters.get_character(character.id) == nil
    end

    test "broadcasts character deletion via WebSocket", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      campaign: _campaign
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}")
      assert response(conn, 204)

      # Verify character is actually deleted from database
      assert Characters.get_character(character.id) == nil
      # TODO: Add proper WebSocket testing once Phoenix Channel test infrastructure is complete
    end

    test "returns forbidden when user is not owner", %{
      conn: conn,
      player: player,
      character: character
    } do
      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end
  end

  describe "duplicate" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Original Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC", "MainAttack" => 13}
        })

      %{character: character}
    end

    test "duplicates character for user with access", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{character.id}/duplicate")
      response = json_response(conn, 201)

      assert response["name"] == "Original Character (1)"
      assert response["action_values"]["Type"] == "PC"
      assert response["user_id"] == gm.id
    end

    test "returns forbidden when user has no access", %{conn: conn, character: character} do
      {:ok, other_user} =
        Accounts.create_user(%{
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
      {:ok, _} =
        Characters.create_character(%{
          name: "Maverick Cop",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC", "Archetype" => "Maverick Cop"}
        })

      {:ok, _} =
        Characters.create_character(%{
          name: "Masked Avenger",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC", "Archetype" => "Masked Avenger"}
        })

      {:ok, _} =
        Characters.create_character(%{
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

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
