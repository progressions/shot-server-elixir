defmodule ShotElixir.SitesTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Sites
  alias ShotElixir.Sites.{Site, Attunement}
  alias ShotElixir.Media
  alias ShotElixir.Campaigns.Campaign
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

    # Insert campaign directly to bypass CampaignSeederWorker that runs in Oban inline mode
    {:ok, campaign} =
      %Campaign{}
      |> Ecto.Changeset.change(%{
        name: "Sites Test Campaign",
        user_id: user.id
      })
      |> Repo.insert()

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

  describe "update_site/2" do
    test "removes characters when character_ids is updated without them", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site with Characters",
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

      # Add both characters to the site via attunements
      {:ok, attunement1} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character1.id
        })

      {:ok, attunement2} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character2.id
        })

      # Update site with only character1 in character_ids (removing character2)
      {:ok, _updated_site} =
        Sites.update_site(site, %{
          "character_ids" => [character1.id]
        })

      # attunement1 should still exist
      assert Repo.get(Attunement, attunement1.id) != nil

      # attunement2 should be deleted
      assert Repo.get(Attunement, attunement2.id) == nil
    end

    test "removes all characters when character_ids is empty list", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site to Clear",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Character to Remove",
          campaign_id: campaign.id
        })

      {:ok, attunement} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character.id
        })

      # Update site with empty character_ids
      {:ok, _updated_site} =
        Sites.update_site(site, %{
          "character_ids" => []
        })

      # Attunement should be deleted
      assert Repo.get(Attunement, attunement.id) == nil
    end

    test "does not affect attunements when character_ids is not provided", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site with Stable Characters",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Stable Character",
          campaign_id: campaign.id
        })

      {:ok, attunement} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character.id
        })

      # Update site without character_ids (just changing name)
      {:ok, _updated_site} =
        Sites.update_site(site, %{
          "name" => "Renamed Site"
        })

      # Attunement should still exist
      assert Repo.get(Attunement, attunement.id) != nil
    end

    test "adds new characters when character_ids includes new ones", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site to Add Characters",
          campaign_id: campaign.id
        })

      {:ok, character1} =
        Characters.create_character(%{
          name: "Existing Character",
          campaign_id: campaign.id
        })

      {:ok, character2} =
        Characters.create_character(%{
          name: "New Character",
          campaign_id: campaign.id
        })

      # Add character1 to the site
      {:ok, _attunement1} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character1.id
        })

      # Update site with both characters (adding character2)
      {:ok, _updated_site} =
        Sites.update_site(site, %{
          "character_ids" => [character1.id, character2.id]
        })

      # Both characters should now be attuned
      attunements = Sites.list_site_attunements(site.id)
      character_ids = Enum.map(attunements, & &1.character_id)

      assert character1.id in character_ids
      assert character2.id in character_ids
      assert length(attunements) == 2
    end

    test "handles complete replacement of characters", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Site for Complete Replacement",
          campaign_id: campaign.id
        })

      {:ok, old_character} =
        Characters.create_character(%{
          name: "Old Character",
          campaign_id: campaign.id
        })

      {:ok, new_character} =
        Characters.create_character(%{
          name: "New Character",
          campaign_id: campaign.id
        })

      # Add old_character to the site
      {:ok, old_attunement} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: old_character.id
        })

      # Update site to replace old_character with new_character
      {:ok, _updated_site} =
        Sites.update_site(site, %{
          "character_ids" => [new_character.id]
        })

      # old_attunement should be deleted
      assert Repo.get(Attunement, old_attunement.id) == nil

      # new_character should be attuned
      attunements = Sites.list_site_attunements(site.id)
      character_ids = Enum.map(attunements, & &1.character_id)

      assert new_character.id in character_ids
      refute old_character.id in character_ids
      assert length(attunements) == 1
    end
  end
end
