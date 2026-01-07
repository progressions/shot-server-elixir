defmodule ShotElixir.Parties.SlotManagementTest do
  use ShotElixir.DataCase, async: true
  alias ShotElixir.{Parties, Campaigns, Characters, Accounts}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        user_id: user.id
      })

    {:ok, party} =
      Parties.create_party(%{
        name: "Test Party",
        campaign_id: campaign.id
      })

    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id
      })

    %{user: user, campaign: campaign, party: party, character: character}
  end

  describe "apply_template/2" do
    test "creates slots from template", %{party: party} do
      assert {:ok, updated_party} = Parties.apply_template(party.id, "boss_fight")

      slots = Parties.list_slots(party.id)
      assert length(slots) == 4

      roles = Enum.map(slots, & &1.role)
      assert :boss in roles
      assert :mook in roles
    end

    test "clears existing slots before applying template", %{party: party} do
      # Add some existing slots
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "mook"})

      assert length(Parties.list_slots(party.id)) == 2

      # Apply template
      {:ok, _} = Parties.apply_template(party.id, "simple_encounter")

      # Should have only template slots (2 for simple_encounter)
      slots = Parties.list_slots(party.id)
      assert length(slots) == 2
    end

    test "returns error for invalid template key", %{party: party} do
      assert {:error, :template_not_found} = Parties.apply_template(party.id, "nonexistent")
    end

    test "returns error for invalid party id" do
      assert {:error, :party_not_found} =
               Parties.apply_template(Ecto.UUID.generate(), "boss_fight")
    end

    test "sets correct positions for slots", %{party: party} do
      {:ok, _} = Parties.apply_template(party.id, "mook_horde")

      slots = Parties.list_slots(party.id)
      positions = Enum.map(slots, & &1.position)

      # Positions should be sequential starting from 0
      assert positions == [0, 1, 2]
    end

    test "sets default_mook_count for mook slots", %{party: party} do
      {:ok, _} = Parties.apply_template(party.id, "mook_horde")

      slots = Parties.list_slots(party.id)

      for slot <- slots do
        assert slot.role == :mook
        assert slot.default_mook_count > 0
      end
    end
  end

  describe "add_slot/2" do
    test "creates a slot with role", %{party: party} do
      assert {:ok, slot} = Parties.add_slot(party.id, %{"role" => "boss"})
      assert slot.role == :boss
      assert slot.party_id == party.id
    end

    test "assigns sequential positions", %{party: party} do
      {:ok, slot1} = Parties.add_slot(party.id, %{"role" => "boss"})
      {:ok, slot2} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, slot3} = Parties.add_slot(party.id, %{"role" => "mook"})

      assert slot1.position == 0
      assert slot2.position == 1
      assert slot3.position == 2
    end

    test "can set default_mook_count for mook slots", %{party: party} do
      {:ok, slot} =
        Parties.add_slot(party.id, %{"role" => "mook", "default_mook_count" => 15})

      assert slot.default_mook_count == 15
    end

    test "can assign character when creating slot", %{party: party, character: character} do
      {:ok, slot} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "character_id" => character.id})

      assert slot.character_id == character.id
    end
  end

  describe "update_slot/3" do
    test "updates slot attributes", %{party: party} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "mook", "default_mook_count" => 10})

      {:ok, updated_slot} =
        Parties.update_slot(party.id, slot.id, %{"default_mook_count" => 20})

      assert updated_slot.default_mook_count == 20
    end

    test "can assign character to slot", %{party: party, character: character} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      {:ok, updated_slot} =
        Parties.update_slot(party.id, slot.id, %{"character_id" => character.id})

      assert updated_slot.character_id == character.id
    end

    test "preserves character when updating mook_count (bug fix)", %{
      party: party,
      character: character
    } do
      {:ok, slot} =
        Parties.add_slot(party.id, %{
          "role" => "mook",
          "character_id" => character.id,
          "default_mook_count" => 10
        })

      # Update only mook count
      {:ok, updated_slot} =
        Parties.update_slot(party.id, slot.id, %{"default_mook_count" => 20})

      # Character should still be assigned
      assert updated_slot.character_id == character.id
      assert updated_slot.default_mook_count == 20
    end

    test "returns not_found for slot from different party", %{party: party, campaign: campaign} do
      # Create another party
      {:ok, other_party} =
        Parties.create_party(%{
          name: "Other Party",
          campaign_id: campaign.id
        })

      {:ok, slot_in_other_party} = Parties.add_slot(other_party.id, %{"role" => "boss"})

      # Try to update slot using wrong party_id (security fix)
      assert {:error, :not_found} =
               Parties.update_slot(party.id, slot_in_other_party.id, %{"default_mook_count" => 5})
    end

    test "returns not_found for nonexistent slot", %{party: party} do
      assert {:error, :not_found} =
               Parties.update_slot(party.id, Ecto.UUID.generate(), %{"default_mook_count" => 5})
    end
  end

  describe "remove_slot/2" do
    test "deletes slot from party", %{party: party} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      assert {:ok, _} = Parties.remove_slot(party.id, slot.id)
      assert Parties.list_slots(party.id) == []
    end

    test "reindexes remaining slots after removal", %{party: party} do
      {:ok, slot1} = Parties.add_slot(party.id, %{"role" => "boss"})
      {:ok, slot2} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, slot3} = Parties.add_slot(party.id, %{"role" => "mook"})

      # Remove middle slot
      {:ok, _} = Parties.remove_slot(party.id, slot2.id)

      slots = Parties.list_slots(party.id)
      positions = Enum.map(slots, & &1.position)

      # Positions should be reindexed to 0, 1
      assert positions == [0, 1]
    end

    test "returns not_found for slot from different party (security fix)", %{
      party: party,
      campaign: campaign
    } do
      {:ok, other_party} =
        Parties.create_party(%{
          name: "Other Party",
          campaign_id: campaign.id
        })

      {:ok, slot_in_other_party} = Parties.add_slot(other_party.id, %{"role" => "boss"})

      # Try to remove slot using wrong party_id
      assert {:error, :not_found} = Parties.remove_slot(party.id, slot_in_other_party.id)

      # Slot should still exist in other party
      assert length(Parties.list_slots(other_party.id)) == 1
    end

    test "returns not_found for nonexistent slot", %{party: party} do
      assert {:error, :not_found} = Parties.remove_slot(party.id, Ecto.UUID.generate())
    end
  end

  describe "reorder_slots/2" do
    test "reorders slots to new positions", %{party: party} do
      {:ok, slot1} = Parties.add_slot(party.id, %{"role" => "boss"})
      {:ok, slot2} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, slot3} = Parties.add_slot(party.id, %{"role" => "mook"})

      # Reverse order
      {:ok, _} = Parties.reorder_slots(party.id, [slot3.id, slot2.id, slot1.id])

      slots = Parties.list_slots(party.id)
      ids = Enum.map(slots, & &1.id)

      assert ids == [slot3.id, slot2.id, slot1.id]
    end

    test "updates positions correctly", %{party: party} do
      {:ok, slot1} = Parties.add_slot(party.id, %{"role" => "boss"})
      {:ok, slot2} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      {:ok, _} = Parties.reorder_slots(party.id, [slot2.id, slot1.id])

      slots = Parties.list_slots(party.id)
      slot2_updated = Enum.find(slots, &(&1.id == slot2.id))
      slot1_updated = Enum.find(slots, &(&1.id == slot1.id))

      assert slot2_updated.position == 0
      assert slot1_updated.position == 1
    end
  end

  describe "list_slots/1" do
    test "returns slots ordered by position", %{party: party} do
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "boss"})
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "featured_foe"})
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "mook"})

      slots = Parties.list_slots(party.id)
      positions = Enum.map(slots, & &1.position)

      assert positions == [0, 1, 2]
    end

    test "returns empty list for party with no slots", %{party: party} do
      assert Parties.list_slots(party.id) == []
    end

    test "only returns slots (memberships with roles)", %{party: party, character: character} do
      # Add regular membership (no role)
      {:ok, _} = Parties.add_member(party.id, %{"character_id" => character.id})

      # Add slot (has role)
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      # list_slots should only return the slot
      slots = Parties.list_slots(party.id)
      assert length(slots) == 1
      assert hd(slots).role == :featured_foe
    end
  end

  describe "populate_slot/3" do
    test "assigns character to slot", %{party: party, character: character} do
      {:ok, slot} = Parties.add_slot(party.id, %{"role" => "featured_foe"})

      {:ok, updated_slot} = Parties.populate_slot(party.id, slot.id, character.id)
      assert updated_slot.character_id == character.id
    end

    test "returns error when slot already has vehicle (must clear first)", %{
      party: party,
      character: character,
      campaign: campaign
    } do
      {:ok, vehicle} =
        ShotElixir.Vehicles.create_vehicle(%{
          name: "Test Vehicle",
          campaign_id: campaign.id,
          action_values: %{"frame" => 10, "handling" => 8, "squeal" => 12}
        })

      # Create slot with vehicle assigned
      {:ok, slot} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "vehicle_id" => vehicle.id})

      assert slot.vehicle_id == vehicle.id

      # Attempting to populate with character when vehicle exists should fail
      # (validation prevents having both character_id and vehicle_id)
      assert {:error, _changeset} = Parties.populate_slot(party.id, slot.id, character.id)

      # Clear the slot first, then populate
      {:ok, cleared_slot} = Parties.clear_slot(party.id, slot.id)
      assert cleared_slot.vehicle_id == nil

      {:ok, populated_slot} = Parties.populate_slot(party.id, slot.id, character.id)
      assert populated_slot.character_id == character.id
    end
  end

  describe "clear_slot/2" do
    test "removes character and vehicle from slot", %{party: party, character: character} do
      {:ok, slot} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "character_id" => character.id})

      {:ok, cleared_slot} = Parties.clear_slot(party.id, slot.id)
      assert cleared_slot.character_id == nil
      assert cleared_slot.vehicle_id == nil
    end
  end

  describe "has_composition?/1" do
    test "returns true when party has slots", %{party: party} do
      {:ok, _} = Parties.add_slot(party.id, %{"role" => "boss"})

      assert Parties.has_composition?(party.id) == true
    end

    test "returns false when party has no slots", %{party: party} do
      assert Parties.has_composition?(party.id) == false
    end

    test "returns false when party only has regular memberships", %{
      party: party,
      character: character
    } do
      {:ok, _} = Parties.add_member(party.id, %{"character_id" => character.id})

      assert Parties.has_composition?(party.id) == false
    end
  end
end
