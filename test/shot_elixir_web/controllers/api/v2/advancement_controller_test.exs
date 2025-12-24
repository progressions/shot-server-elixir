defmodule ShotElixirWeb.Api.V2.AdvancementControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Characters, Campaigns, Accounts, Repo}
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
        description: "Test campaign for advancements",
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

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gamemaster,
     player: player,
     campaign: campaign,
     character: character}
  end

  describe "index" do
    test "lists all advancements for a character in descending order", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      now = DateTime.utc_now()

      {:ok, advancement1} =
        Characters.create_advancement(character.id, %{description: "First advancement"})

      advancement1
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -1, :second)})
      |> Repo.update!()

      {:ok, _advancement2} =
        Characters.create_advancement(character.id, %{description: "Second advancement"})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/advancements")
      response = json_response(conn, 200)

      assert length(response) == 2
      # Verify descending order - second advancement (most recent) should be first
      first_response = Enum.at(response, 0)
      second_response = Enum.at(response, 1)

      assert first_response["description"] == "Second advancement"
      assert second_response["description"] == "First advancement"
    end

    test "returns empty list when character has no advancements", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/advancements")
      response = json_response(conn, 200)

      assert response == []
    end

    test "returns 404 for non-existent character", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/characters/#{non_existent_id}/advancements")
      assert json_response(conn, 404)["error"] == "Character not found"
    end
  end

  describe "create" do
    test "creates advancement with valid data", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/advancements",
          advancement: %{description: "New advancement"}
        )

      response = json_response(conn, 201)
      assert response["description"] == "New advancement"
      assert response["character_id"] == character.id
      assert response["id"] != nil
      assert response["created_at"] != nil
      assert response["updated_at"] != nil
    end

    test "player can create advancement for their own character", %{
      conn: conn,
      player: player,
      character: character
    } do
      conn = authenticate(conn, player)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/advancements",
          advancement: %{description: "Player advancement"}
        )

      response = json_response(conn, 201)
      assert response["description"] == "Player advancement"
    end

    test "allows creating advancement with empty description", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)

      conn =
        post(conn, ~p"/api/v2/characters/#{character.id}/advancements",
          advancement: %{description: ""}
        )

      response = json_response(conn, 201)
      assert response["description"] == nil
      assert response["character_id"] == character.id
    end

    test "returns 404 for non-existent character", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/v2/characters/#{non_existent_id}/advancements",
          advancement: %{description: "Test"}
        )

      assert json_response(conn, 404)["error"] == "Character not found"
    end
  end

  describe "show" do
    test "gets a specific advancement", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Test advancement"})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement.id}")
      response = json_response(conn, 200)

      assert response["id"] == advancement.id
      assert response["description"] == "Test advancement"
      assert response["character_id"] == character.id
    end

    test "returns 404 for non-existent advancement", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{non_existent_id}")
      assert json_response(conn, 404)["error"] == "Advancement or character not found"
    end

    test "returns 404 for non-existent character", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      non_existent_char_id = Ecto.UUID.generate()
      non_existent_adv_id = Ecto.UUID.generate()

      conn =
        get(
          conn,
          ~p"/api/v2/characters/#{non_existent_char_id}/advancements/#{non_existent_adv_id}"
        )

      assert json_response(conn, 404)["error"] == "Advancement or character not found"
    end
  end

  describe "update" do
    test "updates advancement with valid data", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Original description"})

      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement.id}",
          advancement: %{description: "Updated description"}
        )

      response = json_response(conn, 200)
      assert response["description"] == "Updated description"
      assert response["id"] == advancement.id
    end

    test "preserves created_at timestamp when updating", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Original"})

      original_created_at = advancement.created_at

      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement.id}",
          advancement: %{description: "Updated"}
        )

      response = json_response(conn, 200)
      assert response["description"] == "Updated"

      {:ok, response_created_at, _} = DateTime.from_iso8601(response["created_at"])
      assert DateTime.compare(response_created_at, original_created_at) == :eq
    end

    test "player can update their own character's advancement", %{
      conn: conn,
      player: player,
      character: character
    } do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Original"})

      conn = authenticate(conn, player)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement.id}",
          advancement: %{description: "Player updated"}
        )

      response = json_response(conn, 200)
      assert response["description"] == "Player updated"
    end

    test "returns 404 for non-existent advancement", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{non_existent_id}",
          advancement: %{description: "Updated"}
        )

      assert json_response(conn, 404)["error"] == "Advancement or character not found"
    end
  end

  describe "delete" do
    test "deletes an advancement", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "To be deleted"})

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement.id}")
      assert response(conn, 204)

      # Verify advancement is deleted
      assert Characters.get_advancement(advancement.id) == nil
    end

    test "player can delete their own character's advancement", %{
      conn: conn,
      player: player,
      character: character
    } do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "To be deleted"})

      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement.id}")
      assert response(conn, 204)

      assert Characters.get_advancement(advancement.id) == nil
    end

    test "deletion without confirmation", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      {:ok, advancement1} =
        Characters.create_advancement(character.id, %{description: "First"})

      {:ok, advancement2} =
        Characters.create_advancement(character.id, %{description: "Second"})

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{advancement1.id}")
      assert response(conn, 204)

      # Verify only one advancement remains
      advancements = Characters.list_advancements(character.id)
      assert length(advancements) == 1
      assert Enum.at(advancements, 0).id == advancement2.id
    end

    test "returns 404 for non-existent advancement", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()

      conn =
        delete(conn, ~p"/api/v2/characters/#{character.id}/advancements/#{non_existent_id}")

      assert json_response(conn, 404)["error"] == "Advancement or character not found"
    end
  end

  describe "authorization" do
    test "gamemaster can manage any character's advancements", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      {:ok, player_char} =
        Characters.create_character(%{
          name: "Player's Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      conn = authenticate(conn, gm)

      # GM can create advancement for player's character
      conn =
        post(conn, ~p"/api/v2/characters/#{player_char.id}/advancements",
          advancement: %{description: "GM created"}
        )

      response = json_response(conn, 201)
      assert response["description"] == "GM created"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
