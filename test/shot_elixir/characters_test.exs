defmodule ShotElixir.CharactersTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Characters
  alias ShotElixir.Campaigns
  alias ShotElixir.Fights
  alias ShotElixir.Repo

  setup do
    # Create a user and a campaign to own the characters and fights
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "testuser@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign for Characters",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "list_campaign_characters/3" do
    test "with a fight_id, returns characters in both the campaign AND the fight", %{
      campaign: campaign
    } do
      # Create a fight associated with the campaign
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      # Create characters in the campaign
      {:ok, char1} =
        Characters.create_character(%{name: "Character 1", campaign_id: campaign.id})

      {:ok, char2} =
        Characters.create_character(%{name: "Character 2", campaign_id: campaign.id})

      {:ok, char3} =
        Characters.create_character(%{name: "Character 3", campaign_id: campaign.id})

      # Create a character in a different campaign to verify campaign filter still applies
      {:ok, other_campaign} =
        Campaigns.create_campaign(%{name: "Other Campaign", user_id: campaign.user_id})

      {:ok, char_other_campaign} =
        Characters.create_character(%{name: "Character Other", campaign_id: other_campaign.id})

      # Add char1 and char2 to the fight (in campaign)
      Repo.insert!(%Fights.Shot{fight_id: fight.id, character_id: char1.id, shot: 10})
      Repo.insert!(%Fights.Shot{fight_id: fight.id, character_id: char2.id, shot: 12})

      # Also add the other campaign character to fight (should be filtered out by campaign_id)
      Repo.insert!(%Fights.Shot{
        fight_id: fight.id,
        character_id: char_other_campaign.id,
        shot: 14
      })

      # Call the function with campaign_id and fight_id
      # Should return only characters that are BOTH in the campaign AND in the fight
      response =
        Characters.list_campaign_characters(
          campaign.id,
          %{"fight_id" => fight.id},
          nil
        )

      # Assertions - should only return char1 and char2 (in campaign AND fight)
      # char3 is excluded (in campaign but not in fight)
      # char_other_campaign is excluded (in fight but not in campaign)
      assert length(response.characters) == 2
      character_ids = Enum.map(response.characters, & &1.id)
      assert char1.id in character_ids
      assert char2.id in character_ids
      refute char3.id in character_ids
      refute char_other_campaign.id in character_ids
    end
  end

  describe "advancements" do
    setup %{campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      {:ok, character: character}
    end

    test "list_advancements/1 returns all advancements for a character in descending order", %{
      character: character
    } do
      {:ok, _advancement1} =
        Characters.create_advancement(character.id, %{description: "First advancement"})

      :timer.sleep(100)

      {:ok, _advancement2} =
        Characters.create_advancement(character.id, %{description: "Second advancement"})

      advancements = Characters.list_advancements(character.id)

      assert length(advancements) == 2
      # Verify the most recent advancement is first
      first_advancement = Enum.at(advancements, 0)
      second_advancement = Enum.at(advancements, 1)

      # The first advancement should have a created_at >= the second one (descending order)
      assert DateTime.compare(first_advancement.created_at, second_advancement.created_at) in [
               :gt,
               :eq
             ]

      # Verify both advancements are present by description
      descriptions = Enum.map(advancements, & &1.description)
      assert "First advancement" in descriptions
      assert "Second advancement" in descriptions
    end

    test "list_advancements/1 returns empty list when character has no advancements", %{
      character: character
    } do
      advancements = Characters.list_advancements(character.id)
      assert advancements == []
    end

    test "get_advancement!/1 returns the advancement with given id", %{character: character} do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Test advancement"})

      fetched_advancement = Characters.get_advancement!(advancement.id)
      assert fetched_advancement.id == advancement.id
      assert fetched_advancement.description == "Test advancement"
    end

    test "get_advancement/1 returns the advancement with given id", %{character: character} do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Test advancement"})

      fetched_advancement = Characters.get_advancement(advancement.id)
      assert fetched_advancement.id == advancement.id
      assert fetched_advancement.description == "Test advancement"
    end

    test "get_advancement/1 returns nil for non-existent id" do
      result = Characters.get_advancement(Ecto.UUID.generate())
      assert result == nil
    end

    test "create_advancement/2 with valid data creates an advancement", %{character: character} do
      assert {:ok, advancement} =
               Characters.create_advancement(character.id, %{
                 description: "Increased Leadership skill"
               })

      assert advancement.description == "Increased Leadership skill"
      assert advancement.character_id == character.id
      assert advancement.created_at != nil
      assert advancement.updated_at != nil
    end

    test "create_advancement/2 with empty description is valid", %{character: character} do
      assert {:ok, advancement} = Characters.create_advancement(character.id, %{description: ""})

      assert advancement.description == nil
      assert advancement.character_id == character.id
    end

    test "update_advancement/2 with valid data updates the advancement", %{character: character} do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Original description"})

      assert {:ok, updated_advancement} =
               Characters.update_advancement(advancement, %{
                 description: "Updated description"
               })

      assert updated_advancement.description == "Updated description"
      assert updated_advancement.id == advancement.id
    end

    test "update_advancement/2 preserves created_at timestamp", %{character: character} do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "Original description"})

      original_created_at = advancement.created_at
      :timer.sleep(10)

      {:ok, updated_advancement} =
        Characters.update_advancement(advancement, %{description: "Updated description"})

      assert DateTime.compare(updated_advancement.created_at, original_created_at) == :eq
      assert updated_advancement.description == "Updated description"
    end

    test "delete_advancement/1 deletes the advancement", %{character: character} do
      {:ok, advancement} =
        Characters.create_advancement(character.id, %{description: "To be deleted"})

      assert {:ok, _} = Characters.delete_advancement(advancement)
      assert Characters.get_advancement(advancement.id) == nil
    end

    test "advancements are associated with characters", %{character: character} do
      {:ok, advancement1} =
        Characters.create_advancement(character.id, %{description: "First"})

      {:ok, advancement2} =
        Characters.create_advancement(character.id, %{description: "Second"})

      character_with_advancements =
        character
        |> Repo.preload(:advancements)

      advancement_ids =
        Enum.map(character_with_advancements.advancements, & &1.id)

      assert advancement1.id in advancement_ids
      assert advancement2.id in advancement_ids
      assert length(character_with_advancements.advancements) == 2
    end
  end
end
