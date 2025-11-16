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
    test "with a fight_id, returns all characters for that fight, ignoring campaign", %{
      campaign: campaign
    } do
      # Create a fight associated with the campaign
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      # Create three characters
      {:ok, char1} =
        Characters.create_character(%{name: "Character 1", campaign_id: campaign.id})

      {:ok, char2} =
        Characters.create_character(%{name: "Character 2", campaign_id: campaign.id})

      # Create a third character NOT in the campaign to test the filter is ignored
      {:ok, other_campaign} = Campaigns.create_campaign(%{name: "Other Campaign", user_id: campaign.user_id})
      {:ok, char3_other_campaign} =
        Characters.create_character(%{name: "Character 3", campaign_id: other_campaign.id})


      # Associate all three characters with the fight using shots
      Repo.insert!(%Fights.Shot{fight_id: fight.id, character_id: char1.id, shot: 10})
      Repo.insert!(%Fights.Shot{fight_id: fight.id, character_id: char2.id, shot: 12})
      Repo.insert!(%Fights.Shot{fight_id: fight.id, character_id: char3_other_campaign.id, shot: 14})

      # Call the function with the fight_id
      # The first argument (campaign_id) should be ignored by the new logic
      response =
        Characters.list_campaign_characters(
          "00000000-0000-0000-0000-000000000000",
          %{"fight_id" => fight.id},
          nil
        )

      # Assertions
      assert length(response.characters) == 3
      character_ids = Enum.map(response.characters, & &1.id)
      assert char1.id in character_ids
      assert char2.id in character_ids
      assert char3_other_campaign.id in character_ids
    end
  end
end
