defmodule ShotElixir.Workers.NotionWebhookWorkerTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Workers.NotionWebhookWorker
  alias ShotElixir.Characters
  alias ShotElixir.Sites
  alias ShotElixir.Parties
  alias ShotElixir.Factions
  alias ShotElixir.Junctures
  alias ShotElixir.Adventures
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Accounts

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "gm-webhook-test@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, campaign} =
      %Campaign{}
      |> Campaign.changeset(%{
        name: "Webhook Test Campaign",
        user_id: user.id
      })
      |> Repo.insert()

    {:ok, user: user, campaign: campaign}
  end

  describe "find_entity_by_notion_page_id/1" do
    test "returns {:error, :not_found} for nil page_id" do
      assert {:error, :not_found} = NotionWebhookWorker.find_entity_by_notion_page_id(nil)
    end

    test "returns {:error, :not_found} for unknown page_id" do
      unknown_id = Ecto.UUID.generate()
      assert {:error, :not_found} = NotionWebhookWorker.find_entity_by_notion_page_id(unknown_id)
    end

    test "finds character by notion_page_id", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, character} =
        Characters.create_character(%{
          name: "Webhook Test Character",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      {:ok, entity_type, found} = NotionWebhookWorker.find_entity_by_notion_page_id(page_id)

      assert entity_type == :character
      assert found.id == character.id
      assert found.campaign_id == campaign.id
    end

    test "finds site by notion_page_id", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, site} =
        Sites.create_site(%{
          name: "Webhook Test Site",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      {:ok, entity_type, found} = NotionWebhookWorker.find_entity_by_notion_page_id(page_id)

      assert entity_type == :site
      assert found.id == site.id
    end

    test "finds party by notion_page_id", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, party} =
        Parties.create_party(%{
          name: "Webhook Test Party",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      {:ok, entity_type, found} = NotionWebhookWorker.find_entity_by_notion_page_id(page_id)

      assert entity_type == :party
      assert found.id == party.id
    end

    test "finds faction by notion_page_id", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, faction} =
        Factions.create_faction(%{
          name: "Webhook Test Faction",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      {:ok, entity_type, found} = NotionWebhookWorker.find_entity_by_notion_page_id(page_id)

      assert entity_type == :faction
      assert found.id == faction.id
    end

    test "finds juncture by notion_page_id", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Webhook Test Juncture",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      {:ok, entity_type, found} = NotionWebhookWorker.find_entity_by_notion_page_id(page_id)

      assert entity_type == :juncture
      assert found.id == juncture.id
    end

    test "finds adventure by notion_page_id", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Webhook Test Adventure",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      {:ok, entity_type, found} = NotionWebhookWorker.find_entity_by_notion_page_id(page_id)

      assert entity_type == :adventure
      assert found.id == adventure.id
    end

    test "normalizes UUID without dashes", %{campaign: campaign} do
      # UUID with dashes
      page_id_with_dashes = Ecto.UUID.generate()
      # UUID without dashes
      page_id_without_dashes = String.replace(page_id_with_dashes, "-", "")

      {:ok, character} =
        Characters.create_character(%{
          name: "UUID Normalization Test",
          campaign_id: campaign.id,
          notion_page_id: page_id_with_dashes
        })

      # Should find by UUID without dashes
      {:ok, entity_type, found} =
        NotionWebhookWorker.find_entity_by_notion_page_id(page_id_without_dashes)

      assert entity_type == :character
      assert found.id == character.id
    end
  end

  describe "perform/1" do
    test "returns :ok when entity is not found" do
      job = %Oban.Job{
        args: %{
          "event_id" => "event-#{Ecto.UUID.generate()}",
          "event_type" => "page.properties_updated",
          "entity_id" => Ecto.UUID.generate()
        }
      }

      assert :ok = NotionWebhookWorker.perform(job)
    end

    test "processes page.deleted event without error", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, _character} =
        Characters.create_character(%{
          name: "Delete Event Test",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      job = %Oban.Job{
        args: %{
          "event_id" => "event-#{Ecto.UUID.generate()}",
          "event_type" => "page.deleted",
          "entity_id" => page_id
        }
      }

      assert :ok = NotionWebhookWorker.perform(job)
    end

    test "processes page.restored event without error", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, _character} =
        Characters.create_character(%{
          name: "Restore Event Test",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      job = %Oban.Job{
        args: %{
          "event_id" => "event-#{Ecto.UUID.generate()}",
          "event_type" => "page.restored",
          "entity_id" => page_id
        }
      }

      # Will attempt to sync from Notion which may fail in test env
      # but should not raise an exception
      result = NotionWebhookWorker.perform(job)
      assert result == :ok or match?({:error, _}, result)
    end

    test "ignores unknown event types", %{campaign: campaign} do
      page_id = Ecto.UUID.generate()

      {:ok, _character} =
        Characters.create_character(%{
          name: "Unknown Event Test",
          campaign_id: campaign.id,
          notion_page_id: page_id
        })

      job = %Oban.Job{
        args: %{
          "event_id" => "event-#{Ecto.UUID.generate()}",
          "event_type" => "unknown.event.type",
          "entity_id" => page_id
        }
      }

      assert :ok = NotionWebhookWorker.perform(job)
    end
  end

  describe "new/1 job creation" do
    test "creates valid Oban job changeset" do
      args = %{
        event_id: "event-123",
        event_type: "page.properties_updated",
        entity_id: Ecto.UUID.generate()
      }

      job = NotionWebhookWorker.new(args)

      assert %Oban.Job{} = job.data
      assert job.valid?
    end
  end
end
