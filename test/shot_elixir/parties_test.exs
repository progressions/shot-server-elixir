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
end
