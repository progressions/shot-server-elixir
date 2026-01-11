defmodule ShotElixir.Workers.OrphanedImageCleanupWorker do
  @moduledoc """
  Background worker for cleaning up orphaned images.

  Runs periodically to remove images that have been orphaned for more than
  24 hours. This prevents accumulating stale images in ImageKit and the database
  when entities are deleted.

  Orphaned images are created when entities (Characters, Vehicles, Sites, etc.)
  are deleted - their associated images are marked as "orphan" rather than
  immediately deleted, allowing for potential recovery or manual review.
  """

  use Oban.Worker, queue: :images, max_attempts: 3

  alias ShotElixir.Repo
  alias ShotElixir.Media
  alias ShotElixir.Media.MediaImage
  import Ecto.Query
  require Logger

  # Images must be orphaned for at least this long before cleanup
  @orphan_threshold_hours 24

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting orphaned image cleanup")

    # Find images that have been orphaned for longer than the threshold
    cutoff = DateTime.add(DateTime.utc_now(), -@orphan_threshold_hours * 3600, :second)

    orphaned_images =
      from(i in MediaImage,
        where: i.status == "orphan" and i.updated_at < ^cutoff,
        limit: 100
      )
      |> Repo.all()

    if Enum.empty?(orphaned_images) do
      Logger.info("Orphaned image cleanup: no images to clean up")
      :ok
    else
      Logger.info("Orphaned image cleanup: found #{length(orphaned_images)} images to clean up")

      # Delete each image (this handles ImageKit deletion and database cleanup)
      results =
        Enum.map(orphaned_images, fn image ->
          case Media.delete_image(image) do
            {:ok, _} ->
              Logger.debug("Deleted orphaned image: #{image.id}")
              :ok

            {:error, reason} ->
              Logger.warning("Failed to delete orphaned image #{image.id}: #{inspect(reason)}")
              :error
          end
        end)

      deleted_count = Enum.count(results, &(&1 == :ok))
      failed_count = Enum.count(results, &(&1 == :error))

      Logger.info(
        "Orphaned image cleanup completed: #{deleted_count} deleted, #{failed_count} failed"
      )

      :ok
    end
  end
end
