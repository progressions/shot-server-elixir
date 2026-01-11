defmodule ShotElixir.Workers.OrphanedImageCleanupWorkerTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Workers.OrphanedImageCleanupWorker
  alias ShotElixir.Media
  alias ShotElixir.{Accounts, Campaigns}
  alias ShotElixir.Repo

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "cleanup_worker_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Cleanup Worker Test Campaign",
        description: "Test campaign for cleanup worker",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "perform/1" do
    test "cleans up orphaned images older than 24 hours", %{campaign: campaign, user: user} do
      # Create an orphaned image with updated_at more than 24 hours ago
      {:ok, old_orphan} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "orphan",
          imagekit_file_id: "cleanup_test_old",
          imagekit_url: "https://example.com/old_orphan.jpg",
          uploaded_by_id: user.id
        })

      # Manually set updated_at to 25 hours ago
      old_orphan
      |> Ecto.Changeset.change(%{
        updated_at:
          DateTime.utc_now() |> DateTime.add(-25 * 3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      # Run the worker
      job = %Oban.Job{}
      assert :ok = OrphanedImageCleanupWorker.perform(job)

      # Old orphan should be deleted
      assert Media.get_image(old_orphan.id) == nil
    end

    test "keeps orphaned images less than 24 hours old", %{campaign: campaign, user: user} do
      # Create a recently orphaned image
      {:ok, recent_orphan} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "orphan",
          imagekit_file_id: "cleanup_test_recent",
          imagekit_url: "https://example.com/recent_orphan.jpg",
          uploaded_by_id: user.id
        })

      # Run the worker
      job = %Oban.Job{}
      assert :ok = OrphanedImageCleanupWorker.perform(job)

      # Recent orphan should still exist
      assert Media.get_image(recent_orphan.id) != nil
    end

    test "does not affect attached images", %{campaign: campaign, user: user} do
      entity_id = Ecto.UUID.generate()

      # Create an attached image
      {:ok, attached_image} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "attached",
          entity_type: "Character",
          entity_id: entity_id,
          imagekit_file_id: "cleanup_test_attached",
          imagekit_url: "https://example.com/attached.jpg",
          uploaded_by_id: user.id
        })

      # Even if we backdate its updated_at
      attached_image
      |> Ecto.Changeset.change(%{
        updated_at:
          DateTime.utc_now() |> DateTime.add(-48 * 3600, :second) |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      # Run the worker
      job = %Oban.Job{}
      assert :ok = OrphanedImageCleanupWorker.perform(job)

      # Attached image should still exist
      assert Media.get_image(attached_image.id) != nil
    end

    test "handles empty state gracefully" do
      # Run the worker with no orphaned images
      job = %Oban.Job{}
      assert :ok = OrphanedImageCleanupWorker.perform(job)
    end

    test "processes multiple orphaned images in batch", %{campaign: campaign, user: user} do
      cutoff =
        DateTime.utc_now() |> DateTime.add(-25 * 3600, :second) |> DateTime.truncate(:second)

      # Create multiple old orphaned images
      old_ids =
        for i <- 1..5 do
          {:ok, image} =
            Media.create_image(%{
              campaign_id: campaign.id,
              source: "upload",
              status: "orphan",
              imagekit_file_id: "batch_test_#{i}",
              imagekit_url: "https://example.com/batch_#{i}.jpg",
              uploaded_by_id: user.id
            })

          image
          |> Ecto.Changeset.change(%{updated_at: cutoff})
          |> Repo.update!()

          image.id
        end

      # Run the worker
      job = %Oban.Job{}
      assert :ok = OrphanedImageCleanupWorker.perform(job)

      # All old orphans should be deleted
      for id <- old_ids do
        assert Media.get_image(id) == nil
      end
    end
  end
end
