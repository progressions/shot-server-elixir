defmodule ShotElixir.JuncturesTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Junctures
  alias ShotElixir.Characters
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "junctures_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    # Insert campaign directly to bypass CampaignSeederWorker that runs in Oban inline mode
    {:ok, campaign} =
      %Campaign{}
      |> Ecto.Changeset.change(%{
        name: "Junctures Test Campaign",
        user_id: user.id
      })
      |> Repo.insert()

    {:ok, user: user, campaign: campaign}
  end

  describe "update_juncture/2 character_ids sync" do
    test "removes characters when character_ids is updated without them", %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "1850s",
          campaign_id: campaign.id
        })

      {:ok, character1} =
        Characters.create_character(%{
          name: "Character 1",
          campaign_id: campaign.id,
          juncture_id: juncture.id
        })

      {:ok, character2} =
        Characters.create_character(%{
          name: "Character 2",
          campaign_id: campaign.id,
          juncture_id: juncture.id
        })

      # Update juncture with only character1 in character_ids (removing character2)
      {:ok, _updated_juncture} =
        Junctures.update_juncture(juncture, %{
          "character_ids" => [character1.id]
        })

      # character1 should still have juncture_id
      updated_char1 = Repo.get(ShotElixir.Characters.Character, character1.id)
      assert updated_char1.juncture_id == juncture.id

      # character2 should have juncture_id set to nil
      updated_char2 = Repo.get(ShotElixir.Characters.Character, character2.id)
      assert updated_char2.juncture_id == nil
    end

    test "removes all characters when character_ids is empty list", %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Contemporary",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Character to Remove",
          campaign_id: campaign.id,
          juncture_id: juncture.id
        })

      # Update juncture with empty character_ids
      {:ok, _updated_juncture} =
        Junctures.update_juncture(juncture, %{
          "character_ids" => []
        })

      # Character should have juncture_id set to nil
      updated_char = Repo.get(ShotElixir.Characters.Character, character.id)
      assert updated_char.juncture_id == nil
    end

    test "does not affect characters when character_ids is not provided", %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Future",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Stable Character",
          campaign_id: campaign.id,
          juncture_id: juncture.id
        })

      # Update juncture without character_ids (just changing name)
      {:ok, _updated_juncture} =
        Junctures.update_juncture(juncture, %{
          "name" => "Far Future"
        })

      # Character should still be in juncture
      updated_char = Repo.get(ShotElixir.Characters.Character, character.id)
      assert updated_char.juncture_id == juncture.id
    end

    test "adds new characters when character_ids includes new ones", %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Ancient",
          campaign_id: campaign.id
        })

      {:ok, character1} =
        Characters.create_character(%{
          name: "Existing Character",
          campaign_id: campaign.id,
          juncture_id: juncture.id
        })

      {:ok, character2} =
        Characters.create_character(%{
          name: "New Character",
          campaign_id: campaign.id
        })

      # Update juncture with both characters (adding character2)
      {:ok, _updated_juncture} =
        Junctures.update_juncture(juncture, %{
          "character_ids" => [character1.id, character2.id]
        })

      # Both characters should now have juncture_id
      updated_char1 = Repo.get(ShotElixir.Characters.Character, character1.id)
      updated_char2 = Repo.get(ShotElixir.Characters.Character, character2.id)

      assert updated_char1.juncture_id == juncture.id
      assert updated_char2.juncture_id == juncture.id
    end

    test "handles complete replacement of characters", %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Netherworld",
          campaign_id: campaign.id
        })

      {:ok, old_character} =
        Characters.create_character(%{
          name: "Old Character",
          campaign_id: campaign.id,
          juncture_id: juncture.id
        })

      {:ok, new_character} =
        Characters.create_character(%{
          name: "New Character",
          campaign_id: campaign.id
        })

      # Update juncture to replace old_character with new_character
      {:ok, _updated_juncture} =
        Junctures.update_juncture(juncture, %{
          "character_ids" => [new_character.id]
        })

      # old_character should no longer be in juncture
      updated_old = Repo.get(ShotElixir.Characters.Character, old_character.id)
      assert updated_old.juncture_id == nil

      # new_character should now be in juncture
      updated_new = Repo.get(ShotElixir.Characters.Character, new_character.id)
      assert updated_new.juncture_id == juncture.id
    end
  end
end
