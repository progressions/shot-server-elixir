defmodule ShotElixirWeb.Api.V2.ShotSetLocationTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Fights, Characters, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm-shot-location@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a regular player user
    {:ok, player} =
      Accounts.create_user(%{
        email: "player-shot-location@test.com",
        password: "password123",
        first_name: "Regular",
        last_name: "Player",
        gamemaster: false
      })

    # Create non-member user
    {:ok, non_member} =
      Accounts.create_user(%{
        email: "nonmember-shot-location@test.com",
        password: "password123",
        first_name: "Non",
        last_name: "Member",
        gamemaster: false
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Shot Location Test Campaign",
        description: "Campaign for shot location testing",
        user_id: gamemaster.id
      })

    # Add player as member
    {:ok, _membership} = Campaigns.add_member(campaign, player)

    # Set current campaign for users
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})
    {:ok, player} = Accounts.update_user(player, %{current_campaign_id: campaign.id})

    # Create a fight
    {:ok, fight} =
      Fights.create_fight(%{
        name: "Test Fight",
        campaign_id: campaign.id
      })

    # Create a character
    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        character_type: :pc
      })

    # Create a shot for the character in the fight
    {:ok, shot} =
      Fights.create_shot(%{
        fight_id: fight.id,
        character_id: character.id,
        shot: 10
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")

    %{
      conn: conn,
      gamemaster: gamemaster,
      player: player,
      non_member: non_member,
      campaign: campaign,
      fight: fight,
      character: character,
      shot: shot
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "set_location" do
    test "creates new location and assigns to shot", %{
      conn: conn,
      gamemaster: gm,
      shot: shot
    } do
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "Kitchen"})

      response = json_response(conn, 200)
      assert response["created"] == true
      assert response["shot"]["location_id"] != nil
      assert response["shot"]["location_data"]["name"] == "Kitchen"
    end

    test "reuses existing location (case-insensitive)", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      shot: shot
    } do
      # Create existing location
      {:ok, location} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "KITCHEN"})

      response = json_response(conn, 200)
      assert response["created"] == false
      assert response["shot"]["location_id"] == location.id
      assert response["shot"]["location_data"]["name"] == "Kitchen"
    end

    test "player can set location (not gamemaster-only)", %{
      conn: conn,
      player: player,
      shot: shot
    } do
      conn =
        conn
        |> authenticate(player)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "Balcony"})

      response = json_response(conn, 200)
      assert response["created"] == true
      assert response["shot"]["location_id"] != nil
      assert response["shot"]["location_data"]["name"] == "Balcony"
    end

    test "non-member cannot set location", %{
      conn: conn,
      non_member: non_member,
      shot: shot
    } do
      conn =
        conn
        |> authenticate(non_member)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "Kitchen"})

      assert json_response(conn, 403)["error"] == "You must be a campaign member to set locations"
    end

    test "clears location with null", %{conn: conn, gamemaster: gm, fight: fight, shot: shot} do
      # First set a location
      {:ok, _} = Fights.create_fight_location(fight.id, %{"name" => "Kitchen"})

      conn
      |> authenticate(gm)
      |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "Kitchen"})

      # Now clear it
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: nil})

      response = json_response(conn, 200)
      assert response["created"] == false
      assert response["shot"]["location_id"] == nil
      assert response["shot"]["location_data"] == nil
    end

    test "clears location with empty string", %{conn: conn, gamemaster: gm, shot: shot} do
      # First set a location
      conn
      |> authenticate(gm)
      |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "Kitchen"})

      # Now clear it
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: ""})

      response = json_response(conn, 200)
      assert response["shot"]["location_id"] == nil
    end

    test "returns 404 for non-existent shot", %{conn: conn, gamemaster: gm} do
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/shots/#{Ecto.UUID.generate()}/set_location", %{
          location_name: "Kitchen"
        })

      assert json_response(conn, 404)["error"] == "Shot not found"
    end

    test "trims whitespace from location name", %{conn: conn, gamemaster: gm, shot: shot} do
      conn =
        conn
        |> authenticate(gm)
        |> post(~p"/api/v2/shots/#{shot.id}/set_location", %{location_name: "  Kitchen  "})

      response = json_response(conn, 200)
      assert response["shot"]["location_data"]["name"] == "Kitchen"
    end
  end
end
