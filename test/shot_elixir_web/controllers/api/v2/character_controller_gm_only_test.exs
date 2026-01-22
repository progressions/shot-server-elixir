defmodule ShotElixirWeb.Api.V2.CharacterControllerGmOnlyTest do
  @moduledoc """
  Tests for GM-only content visibility in the character API.

  Verifies that `rich_description_gm_only` field is:
  - Included in API responses for GMs (campaign owner, admin, gamemaster members)
  - Excluded from API responses for non-GM users (regular players)
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts
  }

  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create a gamemaster (campaign owner)
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a regular player
    {:ok, player} =
      Accounts.create_user(%{
        email: "player@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create an admin
    {:ok, admin} =
      Accounts.create_user(%{
        email: "admin@example.com",
        password: "password123",
        first_name: "Admin",
        last_name: "User",
        admin: true,
        gamemaster: false
      })

    # Create a second gamemaster who is a member but not owner
    {:ok, other_gm} =
      Accounts.create_user(%{
        email: "othergm@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "GM",
        gamemaster: true
      })

    # Create campaign owned by gamemaster
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign for GM-only content",
        user_id: gamemaster.id
      })

    # Set campaign as current for all users and add them as members
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)
    {:ok, admin_with_campaign} = Accounts.set_current_campaign(admin, campaign.id)
    {:ok, other_gm_with_campaign} = Accounts.set_current_campaign(other_gm, campaign.id)

    {:ok, _} = Campaigns.add_member(campaign, player)
    {:ok, _} = Campaigns.add_member(campaign, admin)
    {:ok, _} = Campaigns.add_member(campaign, other_gm)

    # Create a character with GM-only content
    {:ok, character} =
      Characters.create_character(%{
        name: "Secret Agent NPC",
        campaign_id: campaign.id,
        user_id: gamemaster.id,
        action_values: %{"Type" => "NPC"},
        rich_description: "This is the public description visible to all players.",
        rich_description_gm_only:
          "SECRET: This NPC is actually a double agent working for the Ascended."
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     player: player_with_campaign,
     admin: admin_with_campaign,
     other_gm: other_gm_with_campaign,
     campaign: campaign,
     character: character}
  end

  describe "GM-only content visibility" do
    test "campaign owner (gamemaster) can see GM-only content", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      assert response["id"] == character.id

      assert response["rich_description"] ==
               "This is the public description visible to all players."

      assert response["rich_description_gm_only"] ==
               "SECRET: This NPC is actually a double agent working for the Ascended."
    end

    test "admin can see GM-only content", %{
      conn: conn,
      admin: admin,
      character: character
    } do
      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      assert response["id"] == character.id

      assert response["rich_description_gm_only"] ==
               "SECRET: This NPC is actually a double agent working for the Ascended."
    end

    test "gamemaster member (not owner) can see GM-only content", %{
      conn: conn,
      other_gm: other_gm,
      character: character
    } do
      conn = authenticate(conn, other_gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      assert response["id"] == character.id

      assert response["rich_description_gm_only"] ==
               "SECRET: This NPC is actually a double agent working for the Ascended."
    end

    test "regular player cannot see GM-only content", %{
      conn: conn,
      player: player,
      character: character
    } do
      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      assert response["id"] == character.id

      assert response["rich_description"] ==
               "This is the public description visible to all players."

      # GM-only content should NOT be present in the response
      refute Map.has_key?(response, "rich_description_gm_only")
    end

    test "character without GM-only content returns nil for GMs", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      # Create a character without GM-only content
      {:ok, regular_character} =
        Characters.create_character(%{
          name: "Regular Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "NPC"},
          rich_description: "Just a regular description."
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{regular_character.id}")
      response = json_response(conn, 200)

      assert response["id"] == regular_character.id
      # GM-only field is present but nil
      assert Map.has_key?(response, "rich_description_gm_only")
      assert is_nil(response["rich_description_gm_only"])
    end
  end

  describe "ETag caching with GM-only content" do
    test "GM and player get different ETags for the same character", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      character: character
    } do
      # First request as GM
      gm_conn = authenticate(conn, gm)
      gm_conn = get(gm_conn, ~p"/api/v2/characters/#{character.id}")
      assert gm_conn.status == 200
      gm_etag = get_resp_header(gm_conn, "etag") |> List.first()

      # Second request as player
      player_conn = authenticate(conn, player)
      player_conn = get(player_conn, ~p"/api/v2/characters/#{character.id}")
      assert player_conn.status == 200
      player_etag = get_resp_header(player_conn, "etag") |> List.first()

      # ETags should be different because is_gm differs
      assert gm_etag != player_etag
    end

    test "cached GM response is not served to player (different ETags prevent cache poisoning)",
         %{
           conn: conn,
           gamemaster: gm,
           player: player,
           character: character
         } do
      # GM gets response and ETag
      gm_conn = authenticate(conn, gm)
      gm_conn = get(gm_conn, ~p"/api/v2/characters/#{character.id}")
      gm_etag = get_resp_header(gm_conn, "etag") |> List.first()
      gm_response = json_response(gm_conn, 200)
      assert gm_response["rich_description_gm_only"] != nil

      # Player sends GM's ETag in If-None-Match header
      player_conn = authenticate(conn, player)

      player_conn =
        player_conn
        |> put_req_header("if-none-match", gm_etag)
        |> get(~p"/api/v2/characters/#{character.id}")

      # Player should get full response (not 304) because ETags don't match
      assert player_conn.status == 200
      player_response = json_response(player_conn, 200)
      # Player's response should NOT have GM-only content
      refute Map.has_key?(player_response, "rich_description_gm_only")
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
