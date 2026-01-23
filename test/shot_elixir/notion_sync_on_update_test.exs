defmodule ShotElixir.NotionSyncOnUpdateTest do
  @moduledoc """
  Tests that entities linked to Notion automatically enqueue sync jobs when updated.
  """
  use ShotElixir.DataCase, async: true
  use Oban.Testing, repo: ShotElixir.Repo

  alias ShotElixir.{Characters, Sites, Parties, Factions, Junctures}
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Accounts

  alias ShotElixir.Workers.{
    SyncCharacterToNotionWorker,
    SyncSiteToNotionWorker,
    SyncPartyToNotionWorker,
    SyncFactionToNotionWorker,
    SyncJunctureToNotionWorker
  }

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "notion-sync-test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      %Campaign{}
      |> Campaign.changeset(%{
        name: "Notion Sync Test Campaign",
        user_id: user.id
      })
      |> Repo.insert()

    {:ok, user: user, campaign: campaign}
  end

  describe "Character sync on update" do
    test "enqueues sync job when Notion-linked character is updated", %{campaign: campaign} do
      notion_page_id = Ecto.UUID.generate()

      {:ok, character} =
        Characters.create_character(%{
          name: "Linked Character",
          campaign_id: campaign.id,
          notion_page_id: notion_page_id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Characters.update_character(character, %{name: "Updated Name"})

        assert_enqueued(
          worker: SyncCharacterToNotionWorker,
          args: %{character_id: character.id}
        )
      end)
    end

    test "does not enqueue sync job when non-Notion-linked character is updated", %{
      campaign: campaign
    } do
      {:ok, character} =
        Characters.create_character(%{
          name: "Unlinked Character",
          campaign_id: campaign.id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Characters.update_character(character, %{name: "Updated Name"})

        refute_enqueued(worker: SyncCharacterToNotionWorker)
      end)
    end
  end

  describe "Site sync on update" do
    test "enqueues sync job when Notion-linked site is updated", %{campaign: campaign} do
      notion_page_id = Ecto.UUID.generate()

      {:ok, site} =
        Sites.create_site(%{
          name: "Linked Site",
          campaign_id: campaign.id,
          notion_page_id: notion_page_id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Sites.update_site(site, %{name: "Updated Site Name"})

        assert_enqueued(
          worker: SyncSiteToNotionWorker,
          args: %{site_id: site.id}
        )
      end)
    end

    test "does not enqueue sync job when non-Notion-linked site is updated", %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Unlinked Site",
          campaign_id: campaign.id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Sites.update_site(site, %{name: "Updated Site Name"})

        refute_enqueued(worker: SyncSiteToNotionWorker)
      end)
    end
  end

  describe "Party sync on update" do
    test "enqueues sync job when Notion-linked party is updated", %{campaign: campaign} do
      notion_page_id = Ecto.UUID.generate()

      {:ok, party} =
        Parties.create_party(%{
          name: "Linked Party",
          campaign_id: campaign.id,
          notion_page_id: notion_page_id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Parties.update_party(party, %{name: "Updated Party Name"})

        assert_enqueued(
          worker: SyncPartyToNotionWorker,
          args: %{party_id: party.id}
        )
      end)
    end

    test "does not enqueue sync job when non-Notion-linked party is updated", %{
      campaign: campaign
    } do
      {:ok, party} =
        Parties.create_party(%{
          name: "Unlinked Party",
          campaign_id: campaign.id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Parties.update_party(party, %{name: "Updated Party Name"})

        refute_enqueued(worker: SyncPartyToNotionWorker)
      end)
    end
  end

  describe "Faction sync on update" do
    test "enqueues sync job when Notion-linked faction is updated", %{campaign: campaign} do
      notion_page_id = Ecto.UUID.generate()

      {:ok, faction} =
        Factions.create_faction(%{
          name: "Linked Faction",
          campaign_id: campaign.id,
          notion_page_id: notion_page_id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Factions.update_faction(faction, %{name: "Updated Faction Name"})

        assert_enqueued(
          worker: SyncFactionToNotionWorker,
          args: %{faction_id: faction.id}
        )
      end)
    end

    test "does not enqueue sync job when non-Notion-linked faction is updated", %{
      campaign: campaign
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Unlinked Faction",
          campaign_id: campaign.id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Factions.update_faction(faction, %{name: "Updated Faction Name"})

        refute_enqueued(worker: SyncFactionToNotionWorker)
      end)
    end
  end

  describe "Juncture sync on update" do
    test "enqueues sync job when Notion-linked juncture is updated", %{campaign: campaign} do
      notion_page_id = Ecto.UUID.generate()

      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Linked Juncture",
          campaign_id: campaign.id,
          notion_page_id: notion_page_id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Junctures.update_juncture(juncture, %{name: "Updated Juncture Name"})

        assert_enqueued(
          worker: SyncJunctureToNotionWorker,
          args: %{juncture_id: juncture.id}
        )
      end)
    end

    test "does not enqueue sync job when non-Notion-linked juncture is updated", %{
      campaign: campaign
    } do
      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Unlinked Juncture",
          campaign_id: campaign.id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} = Junctures.update_juncture(juncture, %{name: "Updated Juncture Name"})

        refute_enqueued(worker: SyncJunctureToNotionWorker)
      end)
    end

    test "does not enqueue sync job when skip_notion_sync option is passed", %{campaign: campaign} do
      notion_page_id = Ecto.UUID.generate()

      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Linked Juncture",
          campaign_id: campaign.id,
          notion_page_id: notion_page_id
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _updated} =
          Junctures.update_juncture(juncture, %{name: "Updated Name"}, skip_notion_sync: true)

        refute_enqueued(worker: SyncJunctureToNotionWorker)
      end)
    end
  end
end
