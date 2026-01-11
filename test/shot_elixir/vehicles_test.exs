defmodule ShotElixir.VehiclesTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Vehicles
  alias ShotElixir.Factions
  alias ShotElixir.Campaigns
  alias ShotElixir.Media
  alias ShotElixir.Repo

  # Helper to convert binary UUID to string for comparison
  defp uuid_to_string(uuid) when is_binary(uuid) and byte_size(uuid) == 16 do
    Ecto.UUID.load!(uuid)
  end

  defp uuid_to_string(uuid) when is_binary(uuid), do: uuid

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "testuser@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign for Vehicles",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "list_campaign_vehicles/3 faction filtering" do
    test "factions array only includes factions with active vehicles", %{
      campaign: campaign,
      user: user
    } do
      # Create two factions
      {:ok, faction_with_active} =
        Factions.create_faction(%{
          name: "Active Faction",
          campaign_id: campaign.id
        })

      {:ok, faction_with_inactive} =
        Factions.create_faction(%{
          name: "Inactive Faction",
          campaign_id: campaign.id
        })

      # Create an active vehicle with faction_with_active
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction_with_active.id,
          action_values: %{"Type" => "Car"},
          active: true
        })

      # Create an inactive vehicle with faction_with_inactive
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction_with_inactive.id,
          action_values: %{"Type" => "Car"},
          active: false
        })

      # Fetch vehicles without show_hidden
      result = Vehicles.list_campaign_vehicles(campaign.id, %{}, nil)

      # Should only return the active vehicle
      assert length(result.vehicles) == 1
      assert hd(result.vehicles).name == "Active Vehicle"

      # Factions array should only include the faction with an active vehicle
      faction_ids = Enum.map(result.factions, &uuid_to_string(&1.id))
      assert faction_with_active.id in faction_ids
      refute faction_with_inactive.id in faction_ids
    end

    test "factions array includes all factions when show_hidden is true", %{
      campaign: campaign,
      user: user
    } do
      # Create two factions
      {:ok, faction_with_active} =
        Factions.create_faction(%{
          name: "Active Faction",
          campaign_id: campaign.id
        })

      {:ok, faction_with_inactive} =
        Factions.create_faction(%{
          name: "Inactive Faction",
          campaign_id: campaign.id
        })

      # Create an active vehicle with faction_with_active
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction_with_active.id,
          action_values: %{"Type" => "Car"},
          active: true
        })

      # Create an inactive vehicle with faction_with_inactive
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction_with_inactive.id,
          action_values: %{"Type" => "Car"},
          active: false
        })

      # Fetch vehicles with show_hidden = true
      result = Vehicles.list_campaign_vehicles(campaign.id, %{"show_hidden" => "true"}, nil)

      # Should return both vehicles
      assert length(result.vehicles) == 2

      # Factions array should include both factions
      faction_ids = Enum.map(result.factions, &uuid_to_string(&1.id))
      assert faction_with_active.id in faction_ids
      assert faction_with_inactive.id in faction_ids
    end

    test "faction with only inactive vehicles does not appear in factions array", %{
      campaign: campaign,
      user: user
    } do
      # Create a faction
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Test Faction",
          campaign_id: campaign.id
        })

      # Create multiple inactive vehicles for this faction
      {:ok, _inactive_vehicle1} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle 1",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Car"},
          active: false
        })

      {:ok, _inactive_vehicle2} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle 2",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Motorcycle"},
          active: false
        })

      # Fetch vehicles without show_hidden
      result = Vehicles.list_campaign_vehicles(campaign.id, %{}, nil)

      # Should return no vehicles
      assert length(result.vehicles) == 0

      # Factions array should be empty
      assert result.factions == []
    end
  end

  describe "list_campaign_vehicles/3 archetype filtering" do
    test "archetypes array only includes archetypes from active vehicles", %{
      campaign: campaign,
      user: user
    } do
      # Create an active vehicle with one archetype
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car", "Archetype" => "Sports Car"},
          active: true
        })

      # Create an inactive vehicle with a different archetype
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car", "Archetype" => "Monster Truck"},
          active: false
        })

      # Fetch vehicles without show_hidden
      result = Vehicles.list_campaign_vehicles(campaign.id, %{}, nil)

      # Archetypes array should only include the archetype from the active vehicle
      assert "Sports Car" in result.archetypes
      refute "Monster Truck" in result.archetypes
    end

    test "archetypes array includes all archetypes when show_hidden is true", %{
      campaign: campaign,
      user: user
    } do
      # Create an active vehicle with one archetype
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car", "Archetype" => "Sports Car"},
          active: true
        })

      # Create an inactive vehicle with a different archetype
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car", "Archetype" => "Monster Truck"},
          active: false
        })

      # Fetch vehicles with show_hidden = true
      result = Vehicles.list_campaign_vehicles(campaign.id, %{"show_hidden" => "true"}, nil)

      # Archetypes array should include both archetypes
      assert "Sports Car" in result.archetypes
      assert "Monster Truck" in result.archetypes
    end
  end

  describe "list_campaign_vehicles/3 types filtering" do
    test "types array only includes types from active vehicles", %{
      campaign: campaign,
      user: user
    } do
      # Create an active vehicle with one type
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car"},
          active: true
        })

      # Create an inactive vehicle with a different type
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Helicopter"},
          active: false
        })

      # Fetch vehicles without show_hidden
      result = Vehicles.list_campaign_vehicles(campaign.id, %{}, nil)

      # Types array should only include the type from the active vehicle
      assert "Car" in result.types
      refute "Helicopter" in result.types
    end

    test "types array includes all types when show_hidden is true", %{
      campaign: campaign,
      user: user
    } do
      # Create an active vehicle with one type
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car"},
          active: true
        })

      # Create an inactive vehicle with a different type
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Helicopter"},
          active: false
        })

      # Fetch vehicles with show_hidden = true
      result = Vehicles.list_campaign_vehicles(campaign.id, %{"show_hidden" => "true"}, nil)

      # Types array should include both types
      assert "Car" in result.types
      assert "Helicopter" in result.types
    end
  end

  describe "list_campaign_vehicles/3 mixed scenario" do
    test "faction with both active and inactive vehicles appears in factions array", %{
      campaign: campaign,
      user: user
    } do
      # Create a faction
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Mixed Faction",
          campaign_id: campaign.id
        })

      # Create an active vehicle for this faction
      {:ok, _active_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Active Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Car"},
          active: true
        })

      # Create an inactive vehicle for the same faction
      {:ok, _inactive_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Inactive Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Car"},
          active: false
        })

      # Fetch vehicles without show_hidden
      result = Vehicles.list_campaign_vehicles(campaign.id, %{}, nil)

      # Should only return the active vehicle
      assert length(result.vehicles) == 1
      assert hd(result.vehicles).name == "Active Vehicle"

      # Faction should appear in factions array (it has at least one active vehicle)
      faction_ids = Enum.map(result.factions, &uuid_to_string(&1.id))
      assert faction.id in faction_ids
    end
  end

  describe "delete_vehicle/1" do
    test "hard deletes the vehicle from the database", %{campaign: campaign, user: user} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Vehicle to Delete",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car"}
        })

      assert {:ok, _} = Vehicles.delete_vehicle(vehicle)

      # Vehicle should be completely gone from the database
      assert Repo.get(ShotElixir.Vehicles.Vehicle, vehicle.id) == nil
    end

    test "orphans associated images when vehicle is deleted", %{campaign: campaign, user: user} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Vehicle with Image",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car"}
        })

      # Create an attached image for the vehicle
      {:ok, image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Vehicle",
          entity_id: vehicle.id,
          imagekit_file_id: "vehicle_delete_test",
          imagekit_url: "https://example.com/vehicle.jpg",
          uploaded_by_id: user.id
        })

      assert {:ok, _} = Vehicles.delete_vehicle(vehicle)

      # Image should be orphaned, not deleted
      updated_image = Media.get_image!(image.id)
      assert updated_image.status == "orphan"
      assert updated_image.entity_type == nil
      assert updated_image.entity_id == nil
    end

    test "deletes related shots when vehicle is deleted", %{campaign: campaign, user: user} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Vehicle with Shot",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car"}
        })

      {:ok, fight} =
        ShotElixir.Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      # Create a shot for the vehicle
      {:ok, shot} =
        Repo.insert(%ShotElixir.Fights.Shot{
          fight_id: fight.id,
          vehicle_id: vehicle.id,
          shot: 10
        })

      assert {:ok, _} = Vehicles.delete_vehicle(vehicle)

      # Shot should be deleted
      assert Repo.get(ShotElixir.Fights.Shot, shot.id) == nil
    end

    test "deletes party memberships when vehicle is deleted", %{campaign: campaign, user: user} do
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Vehicle in Party",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Car"}
        })

      {:ok, party} =
        ShotElixir.Parties.create_party(%{
          name: "Test Party",
          campaign_id: campaign.id
        })

      # Create a party membership for the vehicle
      {:ok, membership} =
        Repo.insert(%ShotElixir.Parties.Membership{
          party_id: party.id,
          vehicle_id: vehicle.id
        })

      assert {:ok, _} = Vehicles.delete_vehicle(vehicle)

      # Membership should be deleted
      assert Repo.get(ShotElixir.Parties.Membership, membership.id) == nil
    end
  end
end
