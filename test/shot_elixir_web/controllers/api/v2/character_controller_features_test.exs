defmodule ShotElixirWeb.Api.V2.CharacterControllerFeaturesTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts,
    Schticks,
    Weapons
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

  describe "association rendering" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, schtick} =
        Schticks.create_schtick(%{
          name: "Gun Schtick",
          description: "Gun related ability",
          category: "guns",
          path: "Path of the Gun",
          campaign_id: campaign.id
        })

      {:ok, weapon} =
        Weapons.create_weapon(%{
          name: "Glock 17",
          description: "Reliable pistol",
          damage: 13,
          concealment: 0,
          campaign_id: campaign.id
        })

      %{character: character, schtick: schtick, weapon: weapon}
    end

    test "includes empty associations when none are loaded", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      # Character should have empty arrays for associations that aren't loaded
      assert response["schticks"] == []
      assert response["weapons"] == []
    end

    test "renders basic character data correctly", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}")
      response = json_response(conn, 200)

      char = response
      assert char["id"] == character.id
      assert char["name"] == character.name
      assert char["action_values"]["Type"] == "PC"
      assert char["user_id"] == character.user_id
      assert char["campaign_id"] == character.campaign_id
    end
  end

  describe "wounds and impairments" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
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

      assert response["action_values"]["Body"] == -15
      assert "Impaired" in response["action_values"]["Impairments"]
      assert "Seriously Wounded" in response["action_values"]["Impairments"]
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

      assert response["action_values"]["Body"] == -30
      assert length(response["action_values"]["Impairments"]) == 3
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
