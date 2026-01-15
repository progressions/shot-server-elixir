defmodule ShotElixir.AdventuresTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Adventures
  alias ShotElixir.Adventures.{Adventure, AdventureCharacter, AdventureVillain, AdventureFight}
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Fights
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "adventures_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Adventures Test Campaign",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "create_adventure/1" do
    test "creates adventure with valid attrs", %{campaign: campaign, user: user} do
      attrs = %{
        name: "Chicago On Fire",
        description: "A blazing adventure",
        season: 1,
        campaign_id: campaign.id,
        user_id: user.id
      }

      assert {:ok, adventure} = Adventures.create_adventure(attrs)
      assert adventure.name == "Chicago On Fire"
      assert adventure.description == "A blazing adventure"
      assert adventure.season == 1
      assert adventure.campaign_id == campaign.id
      assert adventure.active == true
    end

    test "fails without required name", %{campaign: campaign, user: user} do
      attrs = %{
        campaign_id: campaign.id,
        user_id: user.id
      }

      assert {:error, changeset} = Adventures.create_adventure(attrs)
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "update_adventure/2" do
    test "updates adventure with valid attrs", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Original Name",
          campaign_id: campaign.id,
          user_id: user.id
        })

      assert {:ok, updated} =
               Adventures.update_adventure(adventure, %{
                 name: "Updated Name",
                 description: "New description",
                 season: 2
               })

      assert updated.name == "Updated Name"
      assert updated.description == "New description"
      assert updated.season == 2
    end
  end

  describe "delete_adventure/1" do
    test "hard deletes the adventure from the database", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure to Delete",
          campaign_id: campaign.id,
          user_id: user.id
        })

      assert {:ok, _} = Adventures.delete_adventure(adventure)

      # Adventure should be completely gone from the database
      assert Repo.get(Adventure, adventure.id) == nil
    end

    test "deletes associated character relationships", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure with Characters",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Hero",
          campaign_id: campaign.id
        })

      # Add character as hero
      {:ok, _} = Adventures.add_character(adventure, character.id)

      assert {:ok, _} = Adventures.delete_adventure(adventure)

      # Adventure character relationship should be deleted
      assert Repo.all(
               from ac in AdventureCharacter,
                 where: ac.adventure_id == ^adventure.id
             ) == []
    end

    test "deletes associated villain relationships", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure with Villains",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Villain",
          campaign_id: campaign.id
        })

      # Add character as villain
      {:ok, _} = Adventures.add_villain(adventure, character.id)

      assert {:ok, _} = Adventures.delete_adventure(adventure)

      # Adventure villain relationship should be deleted
      assert Repo.all(
               from av in AdventureVillain,
                 where: av.adventure_id == ^adventure.id
             ) == []
    end
  end

  describe "add_character/2" do
    test "adds a character as hero to adventure", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Hero",
          campaign_id: campaign.id
        })

      assert {:ok, updated_adventure} = Adventures.add_character(adventure, character.id)
      assert character.id in updated_adventure.character_ids
    end
  end

  describe "remove_character/2" do
    test "removes a character from adventure heroes", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Hero",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_character(adventure, character.id)
      assert character.id in adventure.character_ids

      assert {:ok, updated_adventure} = Adventures.remove_character(adventure, character.id)
      refute character.id in updated_adventure.character_ids
    end
  end

  describe "add_villain/2" do
    test "adds a character as villain to adventure", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Villain",
          campaign_id: campaign.id
        })

      assert {:ok, updated_adventure} = Adventures.add_villain(adventure, character.id)
      assert character.id in updated_adventure.villain_ids
    end
  end

  describe "remove_villain/2" do
    test "removes a character from adventure villains", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Villain",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_villain(adventure, character.id)
      assert character.id in adventure.villain_ids

      assert {:ok, updated_adventure} = Adventures.remove_villain(adventure, character.id)
      refute character.id in updated_adventure.villain_ids
    end
  end

  describe "add_fight/2" do
    test "adds a fight to adventure", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      assert {:ok, updated_adventure} = Adventures.add_fight(adventure, fight.id)
      assert fight.id in updated_adventure.fight_ids
    end
  end

  describe "remove_fight/2" do
    test "removes a fight from adventure", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_fight(adventure, fight.id)
      assert fight.id in adventure.fight_ids

      assert {:ok, updated_adventure} = Adventures.remove_fight(adventure, fight.id)
      refute fight.id in updated_adventure.fight_ids
    end
  end

  describe "duplicate_adventure/1" do
    test "duplicates adventure with new unique name", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Original Adventure",
          description: "The original description",
          season: 1,
          campaign_id: campaign.id,
          user_id: user.id
        })

      assert {:ok, duplicated} = Adventures.duplicate_adventure(adventure)
      assert duplicated.id != adventure.id
      assert duplicated.name == "Original Adventure (1)"
      assert duplicated.description == adventure.description
      assert duplicated.season == adventure.season
      assert duplicated.campaign_id == adventure.campaign_id
    end

    test "copies character associations", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure with Characters",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Hero",
          campaign_id: campaign.id
        })

      {:ok, _} = Adventures.add_character(adventure, character.id)

      assert {:ok, duplicated} = Adventures.duplicate_adventure(adventure)
      assert character.id in duplicated.character_ids
    end

    test "copies villain associations", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure with Villains",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Villain",
          campaign_id: campaign.id
        })

      {:ok, _} = Adventures.add_villain(adventure, character.id)

      assert {:ok, duplicated} = Adventures.duplicate_adventure(adventure)
      assert character.id in duplicated.villain_ids
    end

    test "copies fight associations", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure with Fights",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Epic Battle",
          campaign_id: campaign.id
        })

      {:ok, _} = Adventures.add_fight(adventure, fight.id)

      assert {:ok, duplicated} = Adventures.duplicate_adventure(adventure)
      assert fight.id in duplicated.fight_ids
    end

    test "generates unique name when copy already exists", %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      # Create first copy
      {:ok, copy1} = Adventures.duplicate_adventure(adventure)
      assert copy1.name == "Test Adventure (1)"

      # Create second copy - should get a different name
      {:ok, copy2} = Adventures.duplicate_adventure(adventure)
      assert copy2.name == "Test Adventure (2)"
    end
  end

  describe "list_campaign_adventures/3" do
    test "returns paginated adventures for campaign", %{campaign: campaign, user: user} do
      for i <- 1..5 do
        {:ok, _} =
          Adventures.create_adventure(%{
            name: "Adventure #{i}",
            campaign_id: campaign.id,
            user_id: user.id
          })
      end

      result = Adventures.list_campaign_adventures(campaign.id, %{"page" => 1, "per_page" => 3})

      assert length(result.adventures) == 3
      assert result.meta.total_count == 5
      assert result.meta.total_pages == 2
    end

    test "filters hidden adventures by default", %{campaign: campaign, user: user} do
      {:ok, _visible} =
        Adventures.create_adventure(%{
          name: "Visible Adventure",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })

      {:ok, _hidden} =
        Adventures.create_adventure(%{
          name: "Hidden Adventure",
          campaign_id: campaign.id,
          user_id: user.id,
          active: false
        })

      result = Adventures.list_campaign_adventures(campaign.id, %{}, %{})

      assert length(result.adventures) == 1
      assert hd(result.adventures).name == "Visible Adventure"
    end
  end
end
