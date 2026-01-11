defmodule ShotElixir.PartiesTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Parties
  alias ShotElixir.Parties.{Party, Membership}
  alias ShotElixir.Media
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "parties_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Parties Test Campaign",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "delete_party/1" do
    test "hard deletes the party from the database", %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party to Delete",
          campaign_id: campaign.id
        })

      assert {:ok, _} = Parties.delete_party(party)

      # Party should be completely gone from the database
      assert Repo.get(Party, party.id) == nil
    end

    test "orphans associated images when party is deleted", %{campaign: campaign, user: user} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party with Image",
          campaign_id: campaign.id
        })

      # Create an attached image for the party
      {:ok, image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Party",
          entity_id: party.id,
          imagekit_file_id: "party_delete_test",
          imagekit_url: "https://example.com/party.jpg",
          uploaded_by_id: user.id
        })

      assert {:ok, _} = Parties.delete_party(party)

      # Image should be orphaned, not deleted
      updated_image = Media.get_image!(image.id)
      assert updated_image.status == "orphan"
      assert updated_image.entity_type == nil
      assert updated_image.entity_id == nil
    end

    test "deletes memberships when party is deleted", %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party with Members",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Party Member",
          campaign_id: campaign.id
        })

      # Create a membership for the party
      {:ok, membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: character.id
        })

      assert {:ok, _} = Parties.delete_party(party)

      # Membership should be deleted
      assert Repo.get(Membership, membership.id) == nil
    end
  end

  describe "update_party/2" do
    test "removes characters when character_ids is updated without them", %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party with Characters",
          campaign_id: campaign.id
        })

      {:ok, character1} =
        Characters.create_character(%{
          name: "Character 1",
          campaign_id: campaign.id
        })

      {:ok, character2} =
        Characters.create_character(%{
          name: "Character 2",
          campaign_id: campaign.id
        })

      # Add both characters to the party via memberships
      {:ok, membership1} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: character1.id
        })

      {:ok, membership2} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: character2.id
        })

      # Update party with only character1 in character_ids (removing character2)
      {:ok, updated_party} =
        Parties.update_party(party, %{
          "character_ids" => [character1.id]
        })

      # membership1 should still exist
      assert Repo.get(Membership, membership1.id) != nil

      # membership2 should be deleted
      assert Repo.get(Membership, membership2.id) == nil
    end

    test "removes all characters when character_ids is empty list", %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party to Clear",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Character to Remove",
          campaign_id: campaign.id
        })

      {:ok, membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: character.id
        })

      # Update party with empty character_ids
      {:ok, _updated_party} =
        Parties.update_party(party, %{
          "character_ids" => []
        })

      # Membership should be deleted
      assert Repo.get(Membership, membership.id) == nil
    end

    test "does not affect memberships when character_ids is not provided", %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party with Stable Members",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Stable Character",
          campaign_id: campaign.id
        })

      {:ok, membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: character.id
        })

      # Update party without character_ids (just changing name)
      {:ok, _updated_party} =
        Parties.update_party(party, %{
          "name" => "Renamed Party"
        })

      # Membership should still exist
      assert Repo.get(Membership, membership.id) != nil
    end

    test "removes slot-based memberships (with role) when character_ids is updated", %{
      campaign: campaign
    } do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party with Slots",
          campaign_id: campaign.id
        })

      {:ok, boss} =
        Characters.create_character(%{
          name: "Boss Character",
          campaign_id: campaign.id
        })

      {:ok, featured_foe} =
        Characters.create_character(%{
          name: "Featured Foe",
          campaign_id: campaign.id
        })

      {:ok, mook} =
        Characters.create_character(%{
          name: "Mook Character",
          campaign_id: campaign.id
        })

      # Add characters with roles (slot-based memberships)
      {:ok, boss_membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: boss.id,
          role: :boss
        })

      {:ok, featured_membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: featured_foe.id,
          role: :featured_foe
        })

      {:ok, mook_membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: mook.id,
          role: :mook
        })

      # Update party with only boss in character_ids (removing featured_foe and mook)
      {:ok, _updated_party} =
        Parties.update_party(party, %{
          "character_ids" => [boss.id]
        })

      # boss_membership should still exist
      assert Repo.get(Membership, boss_membership.id) != nil

      # featured_membership and mook_membership should be deleted
      assert Repo.get(Membership, featured_membership.id) == nil
      assert Repo.get(Membership, mook_membership.id) == nil
    end

    test "removes all slot-based memberships when character_ids is empty", %{campaign: campaign} do
      {:ok, party} =
        Parties.create_party(%{
          name: "Party to Clear Slots",
          campaign_id: campaign.id
        })

      {:ok, boss} =
        Characters.create_character(%{
          name: "Boss to Remove",
          campaign_id: campaign.id
        })

      {:ok, mook} =
        Characters.create_character(%{
          name: "Mook to Remove",
          campaign_id: campaign.id
        })

      # Add characters with roles (slot-based memberships)
      {:ok, boss_membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: boss.id,
          role: :boss
        })

      {:ok, mook_membership} =
        Repo.insert(%Membership{
          party_id: party.id,
          character_id: mook.id,
          role: :mook
        })

      # Update party with empty character_ids
      {:ok, _updated_party} =
        Parties.update_party(party, %{
          "character_ids" => []
        })

      # Both memberships should be deleted
      assert Repo.get(Membership, boss_membership.id) == nil
      assert Repo.get(Membership, mook_membership.id) == nil
    end
  end
end
