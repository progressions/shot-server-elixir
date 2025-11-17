defmodule ShotElixir.CharactersTest do
  use ShotElixir.DataCase

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
end
