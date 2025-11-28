defmodule ShotElixir.Services.CampaignSeederServiceTest do
  use ShotElixir.DataCase

  alias ShotElixir.Services.CampaignSeederService
  alias ShotElixir.Campaigns
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Schticks
  alias ShotElixir.Schticks.Schtick
  alias ShotElixir.Weapons
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.Factions
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Accounts
  alias ShotElixir.ImagePositions.ImagePosition

  describe "seed_campaign/1" do
    setup do
      # Create a gamemaster user
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, user: user}
    end

    test "returns error when no master template exists", %{user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "New Campaign",
          user_id: user.id
        })

      # Clear any master template that might exist
      Repo.update_all(Campaign, set: [is_master_template: false])

      assert {:error, :no_master_template} = CampaignSeederService.seed_campaign(campaign)
    end

    test "returns ok when campaign is already seeded", %{user: user} do
      # First insert the campaign
      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Already Seeded",
          user_id: user.id
        })
        |> Repo.insert()

      # Then update it with seeded_at (since changeset doesn't cast seeded_at)
      {:ok, seeded_campaign} =
        campaign
        |> Ecto.Changeset.change(
          seeded_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        )
        |> Repo.update()

      # Should return ok without re-seeding
      assert {:ok, returned} = CampaignSeederService.seed_campaign(seeded_campaign)
      assert returned.id == seeded_campaign.id
    end
  end

  describe "copy_campaign_content/2" do
    setup do
      {:ok, gm} =
        Accounts.create_user(%{
          email: "gm@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      # Create master template campaign
      {:ok, master} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Master Template",
          description: "The master template",
          user_id: gm.id,
          is_master_template: true
        })
        |> Repo.insert()

      # Create target campaign
      {:ok, target} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "New Campaign",
          user_id: gm.id
        })
        |> Repo.insert()

      {:ok, gm: gm, master: master, target: target}
    end

    test "copies schticks from master to target", %{master: master, target: target} do
      # Create schticks in master
      {:ok, schtick1} =
        Schticks.create_schtick(%{
          name: "Lightning Reload",
          category: "Guns",
          path: "Core",
          campaign_id: master.id
        })

      {:ok, _schtick2} =
        Schticks.create_schtick(%{
          name: "Carnival of Carnage",
          category: "Guns",
          path: "Path of the Gun",
          campaign_id: master.id,
          prerequisite_id: schtick1.id
        })

      {:ok, _seeded} = CampaignSeederService.copy_campaign_content(master, target)

      # Verify schticks were copied
      target_schticks = Repo.all(from s in Schtick, where: s.campaign_id == ^target.id)
      assert length(target_schticks) == 2

      # Verify names match
      target_names = Enum.map(target_schticks, & &1.name)
      assert "Lightning Reload" in target_names
      assert "Carnival of Carnage" in target_names

      # Verify prerequisite relationship was preserved
      carnage = Enum.find(target_schticks, &(&1.name == "Carnival of Carnage"))
      reload = Enum.find(target_schticks, &(&1.name == "Lightning Reload"))
      assert carnage.prerequisite_id == reload.id
    end

    test "copies weapons from master to target", %{master: master, target: target} do
      {:ok, _weapon} =
        Weapons.create_weapon(%{
          name: "Beretta 92",
          damage: 10,
          concealment: 3,
          category: "guns",
          campaign_id: master.id
        })

      {:ok, _seeded} = CampaignSeederService.copy_campaign_content(master, target)

      target_weapons = Repo.all(from w in Weapon, where: w.campaign_id == ^target.id)
      assert length(target_weapons) == 1
      assert hd(target_weapons).name == "Beretta 92"
      assert hd(target_weapons).damage == 10
    end

    test "copies factions from master to target", %{master: master, target: target} do
      {:ok, _faction} =
        Factions.create_faction(%{
          name: "The Dragons",
          description: "Chi warriors",
          campaign_id: master.id
        })

      {:ok, _seeded} = CampaignSeederService.copy_campaign_content(master, target)

      target_factions = Repo.all(from f in Faction, where: f.campaign_id == ^target.id)
      assert length(target_factions) == 1
      assert hd(target_factions).name == "The Dragons"
    end

    test "copies junctures with faction references", %{master: master, target: target} do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "The Ascended",
          campaign_id: master.id
        })

      {:ok, _juncture} =
        Junctures.create_juncture(%{
          name: "Contemporary",
          description: "Modern day",
          campaign_id: master.id,
          faction_id: faction.id
        })

      {:ok, _seeded} = CampaignSeederService.copy_campaign_content(master, target)

      target_junctures = Repo.all(from j in Juncture, where: j.campaign_id == ^target.id)
      assert length(target_junctures) == 1
      assert hd(target_junctures).name == "Contemporary"

      # Verify faction reference was mapped to new faction
      target_faction = Repo.get_by(Faction, campaign_id: target.id, name: "The Ascended")
      assert hd(target_junctures).faction_id == target_faction.id
    end

    test "copies template characters with associations", %{gm: gm, master: master, target: target} do
      # Create dependencies first
      {:ok, schtick} =
        Schticks.create_schtick(%{
          name: "Both Guns Blazing",
          category: "Guns",
          campaign_id: master.id
        })

      {:ok, weapon} =
        Weapons.create_weapon(%{
          name: "Desert Eagle",
          damage: 13,
          category: "guns",
          campaign_id: master.id
        })

      {:ok, faction} =
        Factions.create_faction(%{
          name: "The Dragons",
          campaign_id: master.id
        })

      # Create template character
      {:ok, character} =
        Characters.create_character(%{
          name: "Johnny Tso",
          campaign_id: master.id,
          user_id: gm.id,
          is_template: true,
          faction_id: faction.id,
          action_values: %{"Type" => "PC", "Guns" => 15}
        })

      # Add associations
      Repo.insert_all("character_schticks", [
        %{
          character_id: Ecto.UUID.dump!(character.id),
          schtick_id: Ecto.UUID.dump!(schtick.id),
          created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        }
      ])

      Repo.insert_all("carries", [
        %{
          character_id: Ecto.UUID.dump!(character.id),
          weapon_id: Ecto.UUID.dump!(weapon.id),
          created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
          updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        }
      ])

      {:ok, _seeded} = CampaignSeederService.copy_campaign_content(master, target)

      # Verify character was copied
      target_characters = Repo.all(from c in Character, where: c.campaign_id == ^target.id)
      assert length(target_characters) == 1

      new_char = hd(target_characters) |> Repo.preload([:schticks, :weapons])
      assert new_char.name == "Johnny Tso"
      assert new_char.is_template == true

      # Verify faction association
      target_faction = Repo.get_by(Faction, campaign_id: target.id, name: "The Dragons")
      assert new_char.faction_id == target_faction.id

      # Verify schtick associations
      assert length(new_char.schticks) == 1
      assert hd(new_char.schticks).name == "Both Guns Blazing"

      # Verify weapon associations
      assert length(new_char.weapons) == 1
      assert hd(new_char.weapons).name == "Desert Eagle"
    end

    test "does not copy non-template characters", %{gm: gm, master: master, target: target} do
      {:ok, _non_template} =
        Characters.create_character(%{
          name: "Regular NPC",
          campaign_id: master.id,
          user_id: gm.id,
          is_template: false
        })

      {:ok, _template} =
        Characters.create_character(%{
          name: "Template Character",
          campaign_id: master.id,
          user_id: gm.id,
          is_template: true
        })

      {:ok, _seeded} = CampaignSeederService.copy_campaign_content(master, target)

      target_characters = Repo.all(from c in Character, where: c.campaign_id == ^target.id)
      assert length(target_characters) == 1
      assert hd(target_characters).name == "Template Character"
    end

    test "sets seeded_at timestamp", %{master: master, target: target} do
      assert target.seeded_at == nil

      {:ok, seeded} = CampaignSeederService.copy_campaign_content(master, target)

      assert seeded.seeded_at != nil
    end

    test "copies image positions", %{master: master, target: target} do
      # Create an image position for the master campaign
      {:ok, _position} =
        %ImagePosition{}
        |> ImagePosition.changeset(%{
          positionable_type: "Campaign",
          positionable_id: master.id,
          context: "avatar",
          x_position: 50.0,
          y_position: 25.0
        })
        |> Repo.insert()

      {:ok, seeded} = CampaignSeederService.copy_campaign_content(master, target)

      # Verify image position was copied
      target_positions =
        Repo.all(
          from ip in ImagePosition,
            where: ip.positionable_id == ^seeded.id and ip.positionable_type == "Campaign"
        )

      assert length(target_positions) == 1
      assert hd(target_positions).context == "avatar"
      assert hd(target_positions).x_position == 50.0
      assert hd(target_positions).y_position == 25.0
    end
  end

  describe "generate_unique_name/4" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm@example.com",
          password: "password123",
          first_name: "Test",
          last_name: "User",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{name: "Test Campaign", user_id: user.id})
        |> Repo.insert()

      {:ok, campaign: campaign}
    end

    test "returns original name when no conflict", %{campaign: campaign} do
      name =
        CampaignSeederService.generate_unique_name("New Schtick", campaign.id, Schtick, :name)

      assert name == "New Schtick"
    end

    test "appends (1) when name exists", %{campaign: campaign} do
      {:ok, _} =
        Schticks.create_schtick(%{
          name: "Lightning Reload",
          category: "Guns",
          campaign_id: campaign.id
        })

      name =
        CampaignSeederService.generate_unique_name(
          "Lightning Reload",
          campaign.id,
          Schtick,
          :name
        )

      assert name == "Lightning Reload (1)"
    end

    test "increments number when multiple conflicts exist", %{campaign: campaign} do
      {:ok, _} =
        Schticks.create_schtick(%{
          name: "Lightning Reload",
          category: "Guns",
          campaign_id: campaign.id
        })

      {:ok, _} =
        Schticks.create_schtick(%{
          name: "Lightning Reload (1)",
          category: "Guns",
          campaign_id: campaign.id
        })

      name =
        CampaignSeederService.generate_unique_name(
          "Lightning Reload",
          campaign.id,
          Schtick,
          :name
        )

      assert name == "Lightning Reload (2)"
    end

    test "strips existing suffix before generating new one", %{campaign: campaign} do
      {:ok, _} =
        Schticks.create_schtick(%{
          name: "Lightning Reload",
          category: "Guns",
          campaign_id: campaign.id
        })

      # Pass a name that already has a suffix
      name =
        CampaignSeederService.generate_unique_name(
          "Lightning Reload (5)",
          campaign.id,
          Schtick,
          :name
        )

      assert name == "Lightning Reload (1)"
    end
  end
end
