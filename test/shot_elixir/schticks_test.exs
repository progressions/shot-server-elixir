defmodule ShotElixir.SchticksTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Schticks
  alias ShotElixir.Schticks.Schtick
  alias ShotElixir.Media
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "schticks_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Schticks Test Campaign",
        user_id: user.id
      })

    {:ok, character} =
      Characters.create_character(%{
        name: "Schtick Owner",
        campaign_id: campaign.id
      })

    {:ok, user: user, campaign: campaign, character: character}
  end

  describe "delete_schtick/1" do
    test "hard deletes the schtick from the database", %{campaign: campaign, character: character} do
      {:ok, schtick} =
        Schticks.create_schtick(%{
          name: "Schtick to Delete",
          character_id: character.id,
          campaign_id: campaign.id,
          category: "Martial Arts",
          path: "Core"
        })

      assert {:ok, _} = Schticks.delete_schtick(schtick)

      # Schtick should be completely gone from the database
      assert Repo.get(Schtick, schtick.id) == nil
    end

    test "orphans associated images when schtick is deleted", %{
      campaign: campaign,
      character: character,
      user: user
    } do
      {:ok, schtick} =
        Schticks.create_schtick(%{
          name: "Schtick with Image",
          character_id: character.id,
          campaign_id: campaign.id,
          category: "Martial Arts",
          path: "Core"
        })

      # Create an attached image for the schtick
      {:ok, image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Schtick",
          entity_id: schtick.id,
          imagekit_file_id: "schtick_delete_test",
          imagekit_url: "https://example.com/schtick.jpg",
          uploaded_by_id: user.id
        })

      assert {:ok, _} = Schticks.delete_schtick(schtick)

      # Image should be orphaned, not deleted
      updated_image = Media.get_image!(image.id)
      assert updated_image.status == "orphan"
      assert updated_image.entity_type == nil
      assert updated_image.entity_id == nil
    end
  end
end
