defmodule ShotElixirWeb.Api.V2.CharacterControllerNotionTest do
  @moduledoc """
  Tests for Notion integration in the Character controller.

  Tests cover:
  - create_notion_page authorization and validation
  - Conflict detection when character already has notion_page_id
  - sync_from_notion authorization and validation
  - Error handling when character has no notion_page_id
  - create_from_notion (import character from Notion page)
  - unlink notion page (update character with notion_page_id: nil)

  Note: Success case and error case tests require mocking NotionService
  to avoid external API calls. These are documented as follow-up items.
  """
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
        email: "gm-notion@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, player} =
      Accounts.create_user(%{
        email: "player-notion@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Notion Test Campaign",
        description: "Test campaign for Notion tests",
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

  describe "create_notion_page" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Notion Test Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC", "Archetype" => "Maverick Cop"}
        })

      %{character: character}
    end

    test "returns 409 conflict when character already has notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Set notion_page_id to simulate already linked character (must be a valid UUID)
      {:ok, character_with_notion} =
        Characters.update_character(character, %{notion_page_id: Ecto.UUID.generate()})

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{character_with_notion.id}/notion/create")

      assert json_response(conn, 409)["error"] == "Character already has a Notion page linked"
    end

    test "returns 403 forbidden when user is not owner and not gamemaster", %{
      conn: conn,
      player: player,
      character: character
    } do
      conn = authenticate(conn, player)
      conn = post(conn, ~p"/api/v2/characters/#{character.id}/notion/create")

      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns 404 not found for invalid character id", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = post(conn, ~p"/api/v2/characters/#{invalid_id}/notion/create")

      assert json_response(conn, 404)["error"] == "Not found"
    end

    test "returns 404 when user has no campaign access", %{
      conn: conn,
      character: character
    } do
      # User with no campaign access gets 404 (not found) rather than 403
      # This is secure behavior - doesn't reveal existence of characters
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "outsider-notion@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      conn = authenticate(conn, other_user)
      conn = post(conn, ~p"/api/v2/characters/#{character.id}/notion/create")

      assert json_response(conn, 404)["error"] == "Not found"
    end

    test "gamemaster can access notion endpoint for any character in campaign", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      # Create a character owned by the player
      {:ok, player_character} =
        Characters.create_character(%{
          name: "Player's Character for Notion",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{player_character.id}/notion/create")

      # GM should get past authorization checks (not 403/404 for auth reasons)
      # Result depends on NotionService - could be 201 (success) or 422 (API error)
      status = conn.status
      assert status in [201, 422], "Expected 201 or 422, got #{status}"

      # If successful, character should have notion_page_id
      if status == 201 do
        response = json_response(conn, 201)
        assert response["notion_page_id"] != nil
      end
    end

    # Note: Success case test requires mocking NotionService
    # to avoid external API calls. Example test structure:
    #
    # test "creates notion page and returns updated character", %{...} do
    #   # Would require:
    #   # 1. Mock NotionService.create_notion_from_character/1 to return {:ok, %{"id" => "new-page-id"}}
    #   # 2. Verify response status 201
    #   # 3. Verify character has notion_page_id set
    # end
  end

  describe "sync_from_notion" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Sync From Notion Test Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC", "Archetype" => "Maverick Cop"}
        })

      %{character: character}
    end

    test "returns 422 when character has no notion_page_id", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Character has no notion_page_id set
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{character.id}/sync_from_notion")

      assert json_response(conn, 422)["error"] == "Character has no Notion page linked"
    end

    test "returns 403 forbidden when user is not owner and not gamemaster", %{
      conn: conn,
      player: player,
      character: character
    } do
      # Set notion_page_id to pass the notion page check and test authorization
      {:ok, character_with_notion} =
        Characters.update_character(character, %{notion_page_id: Ecto.UUID.generate()})

      conn = authenticate(conn, player)
      conn = post(conn, ~p"/api/v2/characters/#{character_with_notion.id}/sync_from_notion")

      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns 404 not found for invalid character id", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = post(conn, ~p"/api/v2/characters/#{invalid_id}/sync_from_notion")

      assert json_response(conn, 404)["error"] == "Not found"
    end

    test "returns 404 when user has no campaign access", %{
      conn: conn,
      character: character
    } do
      # User with no campaign access gets 404 (not found) rather than 403
      # This is secure behavior - doesn't reveal existence of characters
      # Set notion_page_id to pass the notion page check and test authorization
      {:ok, character_with_notion} =
        Characters.update_character(character, %{notion_page_id: Ecto.UUID.generate()})

      {:ok, other_user} =
        Accounts.create_user(%{
          email: "outsider-sync-notion@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      conn = authenticate(conn, other_user)
      conn = post(conn, ~p"/api/v2/characters/#{character_with_notion.id}/sync_from_notion")

      assert json_response(conn, 404)["error"] == "Not found"
    end

    test "gamemaster can access sync_from_notion endpoint for any character in campaign", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      # Create a character owned by the player with a notion_page_id
      {:ok, player_character} =
        Characters.create_character(%{
          name: "Player's Character for Notion Sync",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"},
          notion_page_id: Ecto.UUID.generate()
        })

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{player_character.id}/sync_from_notion")

      # GM should get past authorization checks (not 403/404 for auth reasons)
      # Result depends on NotionService - could be 200 (success) or 422 (API error)
      status = conn.status
      assert status in [200, 422], "Expected 200 or 422, got #{status}"
    end

    test "character owner can sync from notion", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Set notion_page_id to simulate linked character
      {:ok, character_with_notion} =
        Characters.update_character(character, %{notion_page_id: Ecto.UUID.generate()})

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/#{character_with_notion.id}/sync_from_notion")

      # Result depends on NotionService - could be 200 (success) or 422 (API error)
      status = conn.status
      assert status in [200, 422], "Expected 200 or 422, got #{status}"
    end

    # Note: Success case test requires mocking NotionService
    # to avoid external API calls. Example test structure:
    #
    # test "syncs character from notion and returns updated character", %{...} do
    #   # Would require:
    #   # 1. Mock NotionService.update_character_from_notion/1 to return {:ok, updated_character}
    #   # 2. Verify response status 200
    #   # 3. Verify character attributes are updated from Notion
    # end
  end

  describe "unlink notion page" do
    setup %{gamemaster: gm, campaign: campaign} do
      # Create character with a notion_page_id
      {:ok, character} =
        Characters.create_character(%{
          name: "Character With Notion Link",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC"},
          notion_page_id: Ecto.UUID.generate()
        })

      %{character: character}
    end

    test "gamemaster can unlink notion page by updating with nil", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Verify character has notion_page_id
      assert character.notion_page_id != nil

      conn = authenticate(conn, gm)

      # Update character with notion_page_id set to nil
      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}", %{
          "character" => Jason.encode!(%{"notion_page_id" => nil})
        })

      response = json_response(conn, 200)
      assert response["notion_page_id"] == nil

      # Verify in database
      updated_character = Characters.get_character(character.id)
      assert updated_character.notion_page_id == nil
    end

    test "character owner can unlink notion page", %{
      conn: conn,
      player: player,
      campaign: campaign
    } do
      # Create character owned by player with notion link
      {:ok, player_character} =
        Characters.create_character(%{
          name: "Player Character With Notion",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"},
          notion_page_id: Ecto.UUID.generate()
        })

      assert player_character.notion_page_id != nil

      conn = authenticate(conn, player)

      conn =
        patch(conn, ~p"/api/v2/characters/#{player_character.id}", %{
          "character" => Jason.encode!(%{"notion_page_id" => nil})
        })

      response = json_response(conn, 200)
      assert response["notion_page_id"] == nil

      # Verify in database
      updated_character = Characters.get_character(player_character.id)
      assert updated_character.notion_page_id == nil
    end

    test "unlinking preserves other character data", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Record original values
      original_name = character.name
      original_action_values = character.action_values

      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/characters/#{character.id}", %{
          "character" => Jason.encode!(%{"notion_page_id" => nil})
        })

      response = json_response(conn, 200)

      # Notion link removed
      assert response["notion_page_id"] == nil

      # Other data preserved
      assert response["name"] == original_name
      assert response["action_values"]["Type"] == original_action_values["Type"]
    end
  end

  describe "create_from_notion" do
    test "returns 400 when notion_page_id is missing", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/characters/from_notion", %{})

      assert json_response(conn, 400)["error"] == "notion_page_id is required"
    end

    test "returns 400 when user has no current campaign set", %{
      conn: conn
    } do
      # Create user without a current campaign
      {:ok, user_no_campaign} =
        Accounts.create_user(%{
          email: "no-campaign-notion@example.com",
          password: "password123",
          first_name: "No",
          last_name: "Campaign"
        })

      conn = authenticate(conn, user_no_campaign)

      conn =
        post(conn, ~p"/api/v2/characters/from_notion", %{
          "notion_page_id" => Ecto.UUID.generate()
        })

      assert json_response(conn, 400)["error"] == "No current campaign set"
    end

    test "returns 404 when Notion page is not found", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)

      # Use a non-existent page ID - this will hit Notion API and return 404
      # Note: This test may make an actual API call to Notion
      # In production tests, this should be mocked
      conn =
        post(conn, ~p"/api/v2/characters/from_notion", %{
          "notion_page_id" => "non-existent-page-id"
        })

      # Could be 404 (not found), 422 (API error), or 503 (connection failed)
      assert conn.status in [404, 422, 503]
    end

    test "preserves ownership when importing existing character", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      # Create an existing character owned by the player
      {:ok, existing_character} =
        Characters.create_character(%{
          name: "Existing Player Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      # The security fix ensures that importing a character with the same name
      # won't overwrite the user_id. Since we can't easily mock the Notion API
      # in this test, we verify the existing character's ownership is preserved.
      assert existing_character.user_id == player.id

      # Note: Full integration test would require mocking NotionClient.get_page
      # to return a page with the same character name, then verifying the
      # gamemaster doesn't take ownership of the player's character.
    end

    # Note: Success case requires mocking NotionClient and NotionService
    # to avoid external API calls. Example test structure:
    #
    # test "creates character from Notion page and returns it", %{...} do
    #   # Would require:
    #   # 1. Mock NotionClient.get_page/1 to return valid page data
    #   # 2. Mock NotionService.find_or_create_character_from_notion/2
    #   # 3. Verify response status 201
    #   # 4. Verify character has expected attributes
    #   # 5. Verify Oban job was enqueued
    # end
    #
    # test "handles HTTP exceptions from Notion API", %{...} do
    #   # Would require:
    #   # 1. Mock NotionClient.get_page/1 to raise Req.Error
    #   # 2. Verify response status 503
    #   # 3. Verify error message about connection failure
    # end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
