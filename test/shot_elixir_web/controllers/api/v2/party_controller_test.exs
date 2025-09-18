defmodule ShotElixirWeb.Api.V2.PartyControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.{Campaigns, Parties, Factions, Junctures, Characters, Vehicles, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} = Accounts.create_user(%{
      email: "gm@test.com",
      password: "password123",
      first_name: "Game",
      last_name: "Master",
      gamemaster: true
    })

    # Create a campaign
    {:ok, campaign} = Campaigns.create_campaign(%{
      name: "Party Test Campaign",
      description: "Campaign for party testing",
      user_id: gamemaster.id
    })

    # Set current campaign for gamemaster
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})

    {:ok, faction} = Factions.create_faction(%{
      name: "Test Faction",
      campaign_id: campaign.id
    })

    {:ok, juncture} = Junctures.create_juncture(%{
      name: "Contemporary",
      campaign_id: campaign.id
    })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> authenticate(gamemaster)

    %{
      conn: conn,
      user: gamemaster,
      campaign: campaign,
      faction: faction,
      juncture: juncture
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all parties for campaign", %{conn: conn, campaign: campaign} do
      {:ok, party} = Parties.create_party(%{
        name: "Heroes of Justice",
        campaign_id: campaign.id,
        description: "A brave group"
      })
      conn = get(conn, ~p"/api/v2/parties")
      assert %{"parties" => [returned_party]} = json_response(conn, 200)
      assert returned_party["id"] == party.id
      assert returned_party["name"] == "Heroes of Justice"
    end

    test "returns empty list when no parties", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/parties")
      assert %{"parties" => []} = json_response(conn, 200)
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      {:ok, user_without_campaign} = Accounts.update_user(user, %{current_campaign_id: nil})
      conn =
        conn
        |> authenticate(user_without_campaign)
        |> get(~p"/api/v2/parties")
      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end
  end

  describe "show" do
    setup %{campaign: campaign} do
      {:ok, party} = Parties.create_party(%{
        name: "Heroes of Justice",
        campaign_id: campaign.id,
        description: "A brave group"
      })
      %{party: party}
    end

    test "returns party when found", %{conn: conn, party: party} do
      conn = get(conn, ~p"/api/v2/parties/#{party.id}")
      assert %{"party" => returned_party} = json_response(conn, 200)
      assert returned_party["id"] == party.id
      assert returned_party["name"] == "Heroes of Justice"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}")
      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end

    test "includes characters and vehicles in show response", %{conn: conn, party: party, campaign: campaign} do
      {:ok, character} = Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id
      })
      {:ok, vehicle} = Vehicles.create_vehicle(%{
        name: "Test Vehicle",
        campaign_id: campaign.id,
        action_values: %{
          "frame" => 10,
          "handling" => 8,
          "squeal" => 12
        }
      })
      {:ok, _char_membership} = Parties.add_member(party.id, %{"character_id" => character.id})
      {:ok, _veh_membership} = Parties.add_member(party.id, %{"vehicle_id" => vehicle.id})

      conn = get(conn, ~p"/api/v2/parties/#{party.id}")
      assert %{"party" => returned_party} = json_response(conn, 200)
      assert [char] = returned_party["characters"]
      assert char["name"] == "Test Character"
      assert char["category"] == "character"
      assert [veh] = returned_party["vehicles"]
      assert veh["name"] == "Test Vehicle"
      assert veh["category"] == "vehicle"
    end
  end

  describe "create" do
    test "creates party with valid data", %{conn: conn, campaign: campaign, faction: faction, juncture: juncture} do
      party_params = %{
        "name" => "Brave Warriors",
        "description" => "A courageous band",
        "faction_id" => faction.id,
        "juncture_id" => juncture.id
      }

      conn = post(conn, ~p"/api/v2/parties", party: party_params)
      assert %{"party" => party} = json_response(conn, 201)
      assert party["name"] == "Brave Warriors"
      assert party["description"] == "A courageous band"
      assert party["campaign_id"] == campaign.id
      assert party["faction"]["name"] == "Test Faction"
      assert party["juncture"]["name"] == "Contemporary"
    end

    test "returns error with invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/parties", party: %{})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["name"] != nil
    end
  end

  describe "update" do
    setup %{campaign: campaign, faction: faction} do
      {:ok, party} = Parties.create_party(%{
        name: "Party",
        campaign_id: campaign.id
      })
      %{party: party}
    end

    test "updates party with valid data", %{conn: conn, party: party, faction: faction} do
      conn = patch(conn, ~p"/api/v2/parties/#{party.id}", party: %{
        "name" => "Updated Party",
        "description" => "New description",
        "faction_id" => faction.id
      })
      assert %{"party" => updated_party} = json_response(conn, 200)
      assert updated_party["name"] == "Updated Party"
      assert updated_party["description"] == "New description"
      assert updated_party["faction"]["name"] == "Test Faction"
    end

    test "returns error with invalid data", %{conn: conn, party: party} do
      conn = patch(conn, ~p"/api/v2/parties/#{party.id}", party: %{"name" => ""})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["name"] != nil
    end

    test "returns 404 when party not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}", party: %{"name" => "Test"})
      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end
  end

  describe "delete" do
    setup %{campaign: campaign} do
      {:ok, party} = Parties.create_party(%{
        name: "Party",
        campaign_id: campaign.id
      })
      %{party: party}
    end

    test "soft deletes the party", %{conn: conn, party: party} do
      conn = delete(conn, ~p"/api/v2/parties/#{party.id}")
      assert response(conn, 204)

      updated_party = Parties.get_party(party.id)
      assert updated_party.active == false
    end

    test "returns 404 when party not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}")
      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end
  end

  describe "add_member" do
    setup %{campaign: campaign} do
      {:ok, party} = Parties.create_party(%{
        name: "Party",
        campaign_id: campaign.id
      })
      {:ok, character} = Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id
      })
      {:ok, vehicle} = Vehicles.create_vehicle(%{
        name: "Test Vehicle",
        campaign_id: campaign.id,
        action_values: %{
          "frame" => 10,
          "handling" => 8,
          "squeal" => 12
        }
      })
      %{party: party, character: character, vehicle: vehicle}
    end

    test "adds character to party", %{conn: conn, party: party, character: character} do
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", character_id: character.id)
      assert %{"party" => returned_party} = json_response(conn, 200)
      assert [char] = returned_party["characters"]
      assert char["id"] == character.id
      assert char["name"] == "Test Character"
    end

    test "adds vehicle to party", %{conn: conn, party: party, vehicle: vehicle} do
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", vehicle_id: vehicle.id)
      assert %{"party" => returned_party} = json_response(conn, 200)
      assert [veh] = returned_party["vehicles"]
      assert veh["id"] == vehicle.id
      assert veh["name"] == "Test Vehicle"
    end

    test "returns error when party not found", %{conn: conn, character: character} do
      conn = post(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}/members", character_id: character.id)
      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end

    test "returns error for duplicate membership", %{conn: conn, party: party, character: character} do
      {:ok, _} = Parties.add_member(party.id, %{"character_id" => character.id})
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", character_id: character.id)
      assert %{"errors" => _} = json_response(conn, 422)
    end

    test "returns error when neither character_id nor vehicle_id provided", %{conn: conn, party: party} do
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", %{})
      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "remove_member" do
    setup %{campaign: campaign} do
      {:ok, party} = Parties.create_party(%{
        name: "Party",
        campaign_id: campaign.id
      })
      {:ok, character} = Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id
      })
      {:ok, membership} = Parties.add_member(party.id, %{"character_id" => character.id})
      %{party: party, character: character, membership: membership}
    end

    test "removes member from party", %{conn: conn, party: party, membership: membership} do
      conn = delete(conn, ~p"/api/v2/parties/#{party.id}/members/#{membership.id}")
      assert response(conn, 204)

      # Verify membership is removed
      updated_party = Parties.get_party!(party.id)
      assert updated_party.memberships == []
    end

    test "returns 404 when membership not found", %{conn: conn, party: party} do
      conn = delete(conn, ~p"/api/v2/parties/#{party.id}/members/#{Ecto.UUID.generate()}")
      assert %{"error" => "Membership not found"} = json_response(conn, 404)
    end
  end
end