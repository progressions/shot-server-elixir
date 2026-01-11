defmodule ShotElixir.FactionsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Factions
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Media
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters
  alias ShotElixir.Sites
  alias ShotElixir.Vehicles
  alias ShotElixir.Parties
  alias ShotElixir.Junctures
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "factions_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    # Insert campaign directly to bypass CampaignSeederWorker that runs in Oban inline mode
    {:ok, campaign} =
      %Campaign{}
      |> Ecto.Changeset.change(%{
        name: "Factions Test Campaign",
        user_id: user.id
      })
      |> Repo.insert()

    {:ok, user: user, campaign: campaign}
  end

  describe "delete_faction/1" do
    test "hard deletes the faction from the database", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Faction to Delete",
          campaign_id: campaign.id
        })

      assert {:ok, _} = Factions.delete_faction(faction)

      # Faction should be completely gone from the database
      assert Repo.get(Faction, faction.id) == nil
    end

    test "orphans associated images when faction is deleted", %{campaign: campaign, user: user} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Faction with Image",
          campaign_id: campaign.id
        })

      # Create an attached image for the faction
      {:ok, image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Faction",
          entity_id: faction.id,
          imagekit_file_id: "faction_delete_test",
          imagekit_url: "https://example.com/faction.jpg",
          uploaded_by_id: user.id
        })

      assert {:ok, _} = Factions.delete_faction(faction)

      # Image should be orphaned, not deleted
      updated_image = Media.get_image!(image.id)
      assert updated_image.status == "orphan"
      assert updated_image.entity_type == nil
      assert updated_image.entity_id == nil
    end

    test "nullifies faction_id on related characters when faction is deleted", %{
      campaign: campaign
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Faction with Character",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Faction Member",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      assert {:ok, _} = Factions.delete_faction(faction)

      # Character should still exist but with nullified faction_id
      updated_character = Repo.get(ShotElixir.Characters.Character, character.id)
      assert updated_character != nil
      assert updated_character.faction_id == nil
    end

    test "nullifies faction_id on related sites when faction is deleted", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Faction with Site",
          campaign_id: campaign.id
        })

      {:ok, site} =
        Sites.create_site(%{
          name: "Faction Site",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      assert {:ok, _} = Factions.delete_faction(faction)

      # Site should still exist but with nullified faction_id
      updated_site = Repo.get(ShotElixir.Sites.Site, site.id)
      assert updated_site != nil
      assert updated_site.faction_id == nil
    end

    test "nullifies faction_id on related vehicles when faction is deleted", %{
      campaign: campaign,
      user: user
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Faction with Vehicle",
          campaign_id: campaign.id
        })

      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Faction Vehicle",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Car"}
        })

      assert {:ok, _} = Factions.delete_faction(faction)

      # Vehicle should still exist but with nullified faction_id
      updated_vehicle = Repo.get(ShotElixir.Vehicles.Vehicle, vehicle.id)
      assert updated_vehicle != nil
      assert updated_vehicle.faction_id == nil
    end
  end

  describe "update_faction/2 character_ids sync" do
    test "removes characters when character_ids is updated without them", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Test Faction",
          campaign_id: campaign.id
        })

      {:ok, character1} =
        Characters.create_character(%{
          name: "Character 1",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      {:ok, character2} =
        Characters.create_character(%{
          name: "Character 2",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      # Update faction with only character1 (removing character2)
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "character_ids" => [character1.id]
        })

      updated_char1 = Repo.get(ShotElixir.Characters.Character, character1.id)
      updated_char2 = Repo.get(ShotElixir.Characters.Character, character2.id)

      assert updated_char1.faction_id == faction.id
      assert updated_char2.faction_id == nil
    end

    test "adds new characters when character_ids includes new ones", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Growing Faction",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "New Character",
          campaign_id: campaign.id
        })

      # Update faction to add the character
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "character_ids" => [character.id]
        })

      updated_char = Repo.get(ShotElixir.Characters.Character, character.id)
      assert updated_char.faction_id == faction.id
    end
  end

  describe "update_faction/2 vehicle_ids sync" do
    test "removes vehicles when vehicle_ids is updated without them", %{
      campaign: campaign,
      user: user
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Vehicle Faction",
          campaign_id: campaign.id
        })

      {:ok, vehicle1} =
        Vehicles.create_vehicle(%{
          name: "Vehicle 1",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Car"}
        })

      {:ok, vehicle2} =
        Vehicles.create_vehicle(%{
          name: "Vehicle 2",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "Truck"}
        })

      # Update faction with only vehicle1 (removing vehicle2)
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "vehicle_ids" => [vehicle1.id]
        })

      updated_v1 = Repo.get(ShotElixir.Vehicles.Vehicle, vehicle1.id)
      updated_v2 = Repo.get(ShotElixir.Vehicles.Vehicle, vehicle2.id)

      assert updated_v1.faction_id == faction.id
      assert updated_v2.faction_id == nil
    end
  end

  describe "update_faction/2 site_ids sync" do
    test "removes sites when site_ids is updated without them", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Site Faction",
          campaign_id: campaign.id
        })

      {:ok, site1} =
        Sites.create_site(%{
          name: "Site 1",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      {:ok, site2} =
        Sites.create_site(%{
          name: "Site 2",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      # Update faction with only site1 (removing site2)
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "site_ids" => [site1.id]
        })

      updated_s1 = Repo.get(ShotElixir.Sites.Site, site1.id)
      updated_s2 = Repo.get(ShotElixir.Sites.Site, site2.id)

      assert updated_s1.faction_id == faction.id
      assert updated_s2.faction_id == nil
    end
  end

  describe "update_faction/2 party_ids sync" do
    test "removes parties when party_ids is updated without them", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Party Faction",
          campaign_id: campaign.id
        })

      {:ok, party1} =
        Parties.create_party(%{
          name: "Party 1",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      {:ok, party2} =
        Parties.create_party(%{
          name: "Party 2",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      # Update faction with only party1 (removing party2)
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "party_ids" => [party1.id]
        })

      updated_p1 = Repo.get(ShotElixir.Parties.Party, party1.id)
      updated_p2 = Repo.get(ShotElixir.Parties.Party, party2.id)

      assert updated_p1.faction_id == faction.id
      assert updated_p2.faction_id == nil
    end
  end

  describe "update_faction/2 juncture_ids sync" do
    test "removes junctures when juncture_ids is updated without them", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Juncture Faction",
          campaign_id: campaign.id
        })

      {:ok, juncture1} =
        Junctures.create_juncture(%{
          name: "1850s",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      {:ok, juncture2} =
        Junctures.create_juncture(%{
          name: "Contemporary",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      # Update faction with only juncture1 (removing juncture2)
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "juncture_ids" => [juncture1.id]
        })

      updated_j1 = Repo.get(ShotElixir.Junctures.Juncture, juncture1.id)
      updated_j2 = Repo.get(ShotElixir.Junctures.Juncture, juncture2.id)

      assert updated_j1.faction_id == faction.id
      assert updated_j2.faction_id == nil
    end
  end

  describe "update_faction/2 does not affect relationships when *_ids not provided" do
    test "character assignments remain unchanged without character_ids", %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Stable Faction",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Stable Character",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      # Update faction without character_ids (just changing name)
      {:ok, _updated_faction} =
        Factions.update_faction(faction, %{
          "name" => "Renamed Faction"
        })

      updated_char = Repo.get(ShotElixir.Characters.Character, character.id)
      assert updated_char.faction_id == faction.id
    end
  end
end
