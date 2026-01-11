defmodule ShotElixirWeb.Api.V2.PartyControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Parties, Factions, Junctures, Characters, Vehicles, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Party Test Campaign",
        description: "Campaign for party testing",
        user_id: gamemaster.id
      })

    # Set current campaign for gamemaster
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})

    {:ok, faction} =
      Factions.create_faction(%{
        name: "Test Faction",
        campaign_id: campaign.id
      })

    {:ok, juncture} =
      Junctures.create_juncture(%{
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
      {:ok, party} =
        Parties.create_party(%{
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

    test "includes string ids for parties and factions", %{
      conn: conn,
      campaign: campaign,
      faction: faction,
      user: user
    } do
      {:ok, _party} =
        Parties.create_party(%{
          name: "Encoded Party",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      conn = get(conn, ~p"/api/v2/parties", %{user_id: user.id})
      payload = json_response(conn, 200)

      assert Jason.encode!(payload)
      assert Enum.all?(payload["parties"], &is_binary(&1["id"]))
      assert Enum.all?(payload["factions"], &is_binary(&1["id"]))
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
      {:ok, party} =
        Parties.create_party(%{
          name: "Heroes of Justice",
          campaign_id: campaign.id,
          description: "A brave group"
        })

      %{party: party}
    end

    test "returns party when found", %{conn: conn, party: party} do
      conn = get(conn, ~p"/api/v2/parties/#{party.id}")
      assert returned_party = json_response(conn, 200)
      assert returned_party["id"] == party.id
      assert returned_party["name"] == "Heroes of Justice"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}")
      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end

    test "includes characters and vehicles in show response", %{
      conn: conn,
      party: party,
      campaign: campaign
    } do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
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
      assert returned_party = json_response(conn, 200)
      assert [char] = returned_party["characters"]
      assert char["name"] == "Test Character"
      assert char["category"] == "character"
      assert [veh] = returned_party["vehicles"]
      assert veh["name"] == "Test Vehicle"
      assert veh["category"] == "vehicle"
    end
  end

  describe "create" do
    test "creates party with valid data", %{
      conn: conn,
      campaign: campaign,
      faction: faction,
      juncture: juncture
    } do
      party_params = %{
        "name" => "Brave Warriors",
        "description" => "A courageous band",
        "faction_id" => faction.id,
        "juncture_id" => juncture.id
      }

      conn = post(conn, ~p"/api/v2/parties", party: party_params)
      assert party = json_response(conn, 201)
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
      {:ok, party} =
        Parties.create_party(%{
          name: "Party",
          campaign_id: campaign.id
        })

      %{party: party}
    end

    test "updates party with valid data", %{conn: conn, party: party, faction: faction} do
      conn =
        patch(conn, ~p"/api/v2/parties/#{party.id}",
          party: %{
            "name" => "Updated Party",
            "description" => "New description",
            "faction_id" => faction.id
          }
        )

      assert updated_party = json_response(conn, 200)
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
      {:ok, party} =
        Parties.create_party(%{
          name: "Party",
          campaign_id: campaign.id
        })

      %{party: party}
    end

    test "hard deletes the party", %{conn: conn, party: party} do
      conn = delete(conn, ~p"/api/v2/parties/#{party.id}")
      assert response(conn, 204)

      # Party should be completely removed from database
      assert Parties.get_party(party.id) == nil
    end

    test "returns 404 when party not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}")
      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end
  end

  describe "add_member" do
    setup %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
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
      assert returned_party = json_response(conn, 200)
      assert [char] = returned_party["characters"]
      assert char["id"] == character.id
      assert char["name"] == "Test Character"
    end

    test "adds vehicle to party", %{conn: conn, party: party, vehicle: vehicle} do
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", vehicle_id: vehicle.id)
      assert returned_party = json_response(conn, 200)
      assert [veh] = returned_party["vehicles"]
      assert veh["id"] == vehicle.id
      assert veh["name"] == "Test Vehicle"
    end

    test "returns error when party not found", %{conn: conn, character: character} do
      conn =
        post(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}/members",
          character_id: character.id
        )

      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end

    test "allows duplicate membership (constraint removed in Rails migration 20250928172151)", %{
      conn: conn,
      party: party,
      character: character
    } do
      # First membership
      {:ok, _} = Parties.add_member(party.id, %{"character_id" => character.id})

      # Second membership - now allowed after unique constraint removal
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", character_id: character.id)
      assert _ = json_response(conn, 200)
    end

    test "returns error when neither character_id nor vehicle_id provided", %{
      conn: conn,
      party: party
    } do
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/members", %{})
      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "remove_member" do
    setup %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
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

  describe "slot operations" do
    setup %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      %{party: party, character: character}
    end

    test "add_slot adds a slot to party", %{conn: conn, party: party} do
      conn = post(conn, ~p"/api/v2/parties/#{party.id}/slots", role: "featured_foe")
      assert returned_party = json_response(conn, 201)
      assert [slot] = returned_party["slots"]
      assert slot["role"] == "featured_foe"
    end

    test "update_slot can populate a slot with a character", %{
      conn: conn,
      party: party,
      character: character
    } do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      conn =
        patch(conn, ~p"/api/v2/parties/#{party.id}/slots/#{slot.id}", character_id: character.id)

      assert returned_party = json_response(conn, 200)
      assert [updated_slot] = returned_party["slots"]
      assert updated_slot["character"]["id"] == character.id
    end

    test "update_slot can clear a character from a slot by setting character_id to nil", %{
      conn: conn,
      party: party,
      character: character
    } do
      # First, create a slot with a character
      {:ok, slot} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "character_id" => character.id})

      # Verify the character is assigned (slots are memberships with roles)
      slots = Parties.list_slots(party.id)
      assert [slot_with_char] = slots
      assert slot_with_char.character_id == character.id

      # Now clear the character by sending nil
      conn =
        patch(conn, ~p"/api/v2/parties/#{party.id}/slots/#{slot.id}", character_id: nil)

      assert returned_party = json_response(conn, 200)
      assert [cleared_slot] = returned_party["slots"]
      assert cleared_slot["character"] == nil
    end

    test "remove_slot removes a slot from party", %{conn: conn, party: party} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "mook"})

      conn = delete(conn, ~p"/api/v2/parties/#{party.id}/slots/#{slot.id}")
      assert response(conn, 204)

      # Slots are memberships with roles, check they're removed
      slots = Parties.list_slots(party.id)
      assert slots == []
    end
  end

  describe "list_templates" do
    test "returns all available templates", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/parties/templates")
      assert %{"templates" => templates} = json_response(conn, 200)

      assert is_list(templates)
      assert length(templates) == 8

      # Verify template structure
      template = hd(templates)
      assert Map.has_key?(template, "key")
      assert Map.has_key?(template, "name")
      assert Map.has_key?(template, "description")
      assert Map.has_key?(template, "slots")
    end

    test "templates are sorted by name", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/parties/templates")
      %{"templates" => templates} = json_response(conn, 200)

      names = Enum.map(templates, & &1["name"])
      assert names == Enum.sort(names)
    end
  end

  describe "apply_template" do
    setup %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Template Test Party",
          campaign_id: campaign.id
        })

      %{party: party}
    end

    test "applies template to party", %{conn: conn, party: party} do
      conn =
        post(conn, ~p"/api/v2/parties/#{party.id}/apply_template", template_key: "boss_fight")

      assert returned_party = json_response(conn, 200)
      assert length(returned_party["slots"]) == 4

      roles = Enum.map(returned_party["slots"], & &1["role"])
      assert "boss" in roles
      assert "mook" in roles
    end

    test "clears existing slots before applying", %{conn: conn, party: party} do
      # Add existing slots
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      conn =
        post(conn, ~p"/api/v2/parties/#{party.id}/apply_template",
          template_key: "simple_encounter"
        )

      assert returned_party = json_response(conn, 200)
      # simple_encounter has 2 slots
      assert length(returned_party["slots"]) == 2
    end

    test "returns 404 for invalid template key", %{conn: conn, party: party} do
      conn =
        post(conn, ~p"/api/v2/parties/#{party.id}/apply_template", template_key: "nonexistent")

      assert %{"error" => "Template not found"} = json_response(conn, 404)
    end

    test "returns 404 for invalid party", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}/apply_template",
          template_key: "boss_fight"
        )

      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end
  end

  describe "reorder_slots" do
    setup %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Reorder Test Party",
          campaign_id: campaign.id
        })

      {:ok, slot1} = Parties.add_slot(party.id, %{"role" => "boss"})
      {:ok, slot2} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, slot3} = Parties.add_slot(party.id, %{"role" => "mook"})

      %{party: party, slot1: slot1, slot2: slot2, slot3: slot3}
    end

    test "reorders slots to new positions", %{
      conn: conn,
      party: party,
      slot1: slot1,
      slot2: slot2,
      slot3: slot3
    } do
      # Reverse order
      conn =
        post(conn, ~p"/api/v2/parties/#{party.id}/reorder_slots",
          slot_ids: [slot3.id, slot2.id, slot1.id]
        )

      assert returned_party = json_response(conn, 200)
      slot_ids = Enum.map(returned_party["slots"], & &1["id"])
      assert slot_ids == [slot3.id, slot2.id, slot1.id]
    end

    test "returns 404 for invalid party", %{conn: conn, slot1: slot1} do
      conn =
        post(conn, ~p"/api/v2/parties/#{Ecto.UUID.generate()}/reorder_slots",
          slot_ids: [slot1.id]
        )

      assert %{"error" => "Party not found"} = json_response(conn, 404)
    end
  end

  describe "slot authorization" do
    setup %{campaign: campaign} do
      # Create a player (non-gamemaster) user
      {:ok, player} =
        Accounts.create_user(%{
          email: "player@test.com",
          password: "password123",
          first_name: "Player",
          last_name: "User",
          gamemaster: false
        })

      # Add player to campaign as member
      {:ok, _} = Campaigns.add_member(campaign, player)

      {:ok, player} = Accounts.update_user(player, %{current_campaign_id: campaign.id})

      {:ok, party} =
        Parties.create_party(%{
          name: "Auth Test Party",
          campaign_id: campaign.id
        })

      %{player: player, party: party}
    end

    test "non-gamemaster cannot add slots", %{conn: conn, party: party, player: player} do
      conn =
        conn
        |> authenticate(player)
        |> post(~p"/api/v2/parties/#{party.id}/slots", role: "boss")

      assert %{"error" => "Only gamemaster can modify party composition"} =
               json_response(conn, 403)
    end

    test "non-gamemaster cannot apply templates", %{conn: conn, party: party, player: player} do
      conn =
        conn
        |> authenticate(player)
        |> post(~p"/api/v2/parties/#{party.id}/apply_template", template_key: "boss_fight")

      assert %{"error" => "Only gamemaster can modify party composition"} =
               json_response(conn, 403)
    end

    test "non-gamemaster cannot update slots", %{conn: conn, party: party, player: player} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "boss"})

      conn =
        conn
        |> authenticate(player)
        |> patch(~p"/api/v2/parties/#{party.id}/slots/#{slot.id}", default_mook_count: 10)

      assert %{"error" => "Only gamemaster can modify party composition"} =
               json_response(conn, 403)
    end

    test "non-gamemaster cannot remove slots", %{conn: conn, party: party, player: player} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "mook"})

      conn =
        conn
        |> authenticate(player)
        |> delete(~p"/api/v2/parties/#{party.id}/slots/#{slot.id}")

      assert %{"error" => "Only gamemaster can modify party composition"} =
               json_response(conn, 403)
    end

    test "non-gamemaster cannot reorder slots", %{conn: conn, party: party, player: player} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "boss"})

      conn =
        conn
        |> authenticate(player)
        |> post(~p"/api/v2/parties/#{party.id}/reorder_slots", slot_ids: [slot.id])

      assert %{"error" => "Only gamemaster can modify party composition"} =
               json_response(conn, 403)
    end
  end

  describe "slot security - cross-party protection" do
    setup %{campaign: campaign} do
      {:ok, party1} =
        Parties.create_party(%{
          name: "Party 1",
          campaign_id: campaign.id
        })

      {:ok, party2} =
        Parties.create_party(%{
          name: "Party 2",
          campaign_id: campaign.id
        })

      {:ok, slot_in_party2} = Parties.add_slot(party2.id, %{"role" => "boss"})

      %{party1: party1, party2: party2, slot_in_party2: slot_in_party2}
    end

    test "cannot update slot from different party", %{
      conn: conn,
      party1: party1,
      slot_in_party2: slot_in_party2
    } do
      conn =
        patch(conn, ~p"/api/v2/parties/#{party1.id}/slots/#{slot_in_party2.id}",
          default_mook_count: 99
        )

      assert %{"error" => "Slot not found"} = json_response(conn, 404)
    end

    test "cannot remove slot from different party", %{
      conn: conn,
      party1: party1,
      party2: party2,
      slot_in_party2: slot_in_party2
    } do
      conn = delete(conn, ~p"/api/v2/parties/#{party1.id}/slots/#{slot_in_party2.id}")
      assert %{"error" => "Slot not found"} = json_response(conn, 404)

      # Verify slot still exists in party2
      slots = Parties.list_slots(party2.id)
      assert length(slots) == 1
    end
  end
end
