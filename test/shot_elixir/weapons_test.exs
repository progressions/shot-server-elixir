defmodule ShotElixir.WeaponsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Weapons
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.Media
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "weapons_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Weapons Test Campaign",
        user_id: user.id
      })

    {:ok, character} =
      Characters.create_character(%{
        name: "Weapon Owner",
        campaign_id: campaign.id
      })

    {:ok, user: user, campaign: campaign, character: character}
  end

  describe "delete_weapon/1" do
    test "hard deletes the weapon from the database", %{campaign: campaign, character: character} do
      {:ok, weapon} =
        Weapons.create_weapon(%{
          name: "Weapon to Delete",
          character_id: character.id,
          campaign_id: campaign.id,
          damage: "+3",
          concealment: 2
        })

      assert {:ok, _} = Weapons.delete_weapon(weapon)

      # Weapon should be completely gone from the database
      assert Repo.get(Weapon, weapon.id) == nil
    end

    test "orphans associated images when weapon is deleted", %{
      campaign: campaign,
      character: character,
      user: user
    } do
      {:ok, weapon} =
        Weapons.create_weapon(%{
          name: "Weapon with Image",
          character_id: character.id,
          campaign_id: campaign.id,
          damage: "+3",
          concealment: 2
        })

      # Create an attached image for the weapon
      {:ok, image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Weapon",
          entity_id: weapon.id,
          imagekit_file_id: "weapon_delete_test",
          imagekit_url: "https://example.com/weapon.jpg",
          uploaded_by_id: user.id
        })

      assert {:ok, _} = Weapons.delete_weapon(weapon)

      # Image should be orphaned, not deleted
      updated_image = Media.get_image!(image.id)
      assert updated_image.status == "orphan"
      assert updated_image.entity_type == nil
      assert updated_image.entity_id == nil
    end
  end
end
