defmodule ShotElixir.FactionsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Factions
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Media
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Sites
  alias ShotElixir.Vehicles
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

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Factions Test Campaign",
        user_id: user.id
      })

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
end
