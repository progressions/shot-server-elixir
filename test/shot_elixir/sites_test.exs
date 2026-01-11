defmodule ShotElixir.SitesTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Sites
  alias ShotElixir.Sites.{Site, Attunement}
  alias ShotElixir.Media
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "sites_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Sites Test Campaign",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "delete_site/1" do
    test "hard deletes the site from the database", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site to Delete",
          campaign_id: campaign.id
        })

      assert {:ok, _} = Sites.delete_site(site)

      # Site should be completely gone from the database
      assert Repo.get(Site, site.id) == nil
    end

    test "orphans associated images when site is deleted", %{campaign: campaign, user: user} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site with Image",
          campaign_id: campaign.id
        })

      # Create an attached image for the site
      {:ok, image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Site",
          entity_id: site.id,
          imagekit_file_id: "site_delete_test",
          imagekit_url: "https://example.com/site.jpg",
          uploaded_by_id: user.id
        })

      assert {:ok, _} = Sites.delete_site(site)

      # Image should be orphaned, not deleted
      updated_image = Media.get_image!(image.id)
      assert updated_image.status == "orphan"
      assert updated_image.entity_type == nil
      assert updated_image.entity_id == nil
    end

    test "deletes attunements when site is deleted", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site with Attunement",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Attuned Character",
          campaign_id: campaign.id
        })

      # Create an attunement for the site
      {:ok, attunement} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character.id
        })

      assert {:ok, _} = Sites.delete_site(site)

      # Attunement should be deleted
      assert Repo.get(Attunement, attunement.id) == nil
    end
  end
end
