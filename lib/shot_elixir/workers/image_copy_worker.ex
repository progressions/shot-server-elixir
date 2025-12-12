defmodule ShotElixir.Workers.ImageCopyWorker do
  @moduledoc """
  Background worker for copying images between entities.

  This worker handles individual image copy operations, allowing for:
  - Independent retry logic per image
  - Parallelization of image copies
  - No blocking of database connections during HTTP requests
  - Progress tracking for campaign seeding

  The worker runs in the :images queue with max 3 attempts.
  """

  use Oban.Worker, queue: :images, max_attempts: 3

  alias ShotElixir.Services.ImageKitImporter
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Repo
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    source_type = args["source_type"]
    source_id = args["source_id"]
    target_type = args["target_type"]
    target_id = args["target_id"]
    campaign_id = args["campaign_id"]
    is_final_attempt = attempt >= max_attempts

    Logger.info(
      "[ImageCopyWorker] Copying image from #{source_type}:#{source_id} to #{target_type}:#{target_id} (attempt #{attempt}/#{max_attempts})"
    )

    try do
      # Get the source and target entities
      with {:ok, source} <- get_entity(source_type, source_id),
           {:ok, target} <- get_entity(target_type, target_id) do
        case ImageKitImporter.copy_image(source, target) do
          {:ok, _attachment} ->
            Logger.info(
              "[ImageCopyWorker] Successfully copied image to #{target_type}:#{target_id}"
            )

            # Success - increment counter
            if campaign_id do
              increment_image_completion(campaign_id)
            end

            :ok

          {:error, :no_image} ->
            # Source has no image - this is fine, not an error
            Logger.debug("[ImageCopyWorker] Source #{source_type}:#{source_id} has no image")

            # No image to copy - increment counter
            if campaign_id do
              increment_image_completion(campaign_id)
            end

            :ok

          {:error, reason} ->
            Logger.error(
              "[ImageCopyWorker] Failed to copy image to #{target_type}:#{target_id}: #{inspect(reason)} (attempt #{attempt}/#{max_attempts})"
            )

            # On final attempt, increment counter before returning error
            # so seeding can complete even if some images fail
            if is_final_attempt && campaign_id do
              Logger.warning(
                "[ImageCopyWorker] Final attempt failed - incrementing counter to prevent seeding from blocking"
              )

              increment_image_completion(campaign_id)
            end

            # Return error to trigger retry (or discard on final attempt)
            {:error, reason}
        end
      else
        {:error, :not_found} ->
          Logger.error("[ImageCopyWorker] Entity not found - discarding job")

          # Still increment progress so seeding can complete
          # (entity was likely deleted, but we don't want to block seeding)
          if campaign_id do
            increment_image_completion(campaign_id)
          end

          # Non-retryable: entity doesn't exist
          {:discard, :entity_not_found}
      end
    rescue
      e ->
        Logger.error("[ImageCopyWorker] Exception while copying image: #{inspect(e)}")
        Logger.error(Exception.format(:error, e, __STACKTRACE__))

        # Increment counter so seeding can complete
        # (we don't want a single failed image to block the entire campaign)
        if campaign_id do
          Logger.warning(
            "[ImageCopyWorker] Incrementing counter despite error to prevent seeding from blocking"
          )

          increment_image_completion(campaign_id)
        end

        # Discard instead of retrying - we've already incremented
        {:discard, :exception}
    end
  end

  @doc """
  Increments the image completion counter for a campaign and checks if seeding is complete.
  Uses atomic SQL UPDATE to prevent race conditions with parallel workers.
  """
  def increment_image_completion(campaign_id) do
    # Use atomic increment to prevent race conditions with parallel workers
    # This ensures each worker's increment is counted even when running concurrently
    query =
      from(c in Campaign,
        where: c.id == ^campaign_id,
        update: [set: [seeding_images_completed: coalesce(c.seeding_images_completed, 0) + 1]],
        select: %{
          seeding_images_completed: c.seeding_images_completed,
          seeding_images_total: c.seeding_images_total,
          user_id: c.user_id
        }
      )

    case Repo.update_all(query, []) do
      {1, [result]} ->
        # Note: The SELECT happens BEFORE the UPDATE in update_all, so we need to add 1
        new_completed = (result.seeding_images_completed || 0) + 1
        images_total = result.seeding_images_total
        user_id = result.user_id

        payload = %{
          seeding_status: "images",
          campaign_id: campaign_id,
          images_total: images_total,
          images_completed: new_completed
        }

        # Broadcast progress to campaign channel
        Phoenix.PubSub.broadcast!(
          ShotElixir.PubSub,
          "campaign:#{campaign_id}",
          {:campaign_broadcast, payload}
        )

        # Also broadcast to user channel for newly created campaigns
        if user_id do
          Phoenix.PubSub.broadcast!(
            ShotElixir.PubSub,
            "user:#{user_id}",
            {:user_broadcast, payload}
          )
        end

        Logger.debug("[ImageCopyWorker] Image progress: #{new_completed}/#{images_total}")

        # Check if all images are done
        if new_completed >= (images_total || 0) do
          # Fetch the full campaign for finalize_seeding
          campaign = Repo.get(Campaign, campaign_id)
          if campaign, do: finalize_seeding(campaign)
        end

      {0, _} ->
        Logger.warning("[ImageCopyWorker] Campaign #{campaign_id} not found for increment")

      other ->
        Logger.error("[ImageCopyWorker] Unexpected result from increment: #{inspect(other)}")
    end
  end

  @doc """
  Marks the campaign seeding as complete.
  """
  def finalize_seeding(%Campaign{} = campaign) do
    Logger.info("[ImageCopyWorker] Finalizing seeding for campaign #{campaign.id}")

    {:ok, _updated} =
      campaign
      |> Ecto.Changeset.change(
        seeding_status: "complete",
        seeded_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      )
      |> Repo.update()

    payload = %{
      seeding_status: "complete",
      campaign_id: campaign.id
    }

    # Broadcast completion to campaign channel
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign.id}",
      {:campaign_broadcast, payload}
    )

    # Also broadcast to user channel for newly created campaigns
    if campaign.user_id do
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "user:#{campaign.user_id}",
        {:user_broadcast, payload}
      )
    end

    # Also broadcast the standard campaign_seeded event for compatibility
    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      "campaign:#{campaign.id}",
      {:campaign_seeded, %{campaign_id: campaign.id}}
    )

    Logger.info("[ImageCopyWorker] Campaign #{campaign.id} seeding complete!")
  end

  # Helper to get entity by type and ID
  defp get_entity(type, id) do
    module = get_module(type)

    case ShotElixir.Repo.get(module, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp get_module("Campaign"), do: ShotElixir.Campaigns.Campaign
  defp get_module("Character"), do: ShotElixir.Characters.Character
  defp get_module("Schtick"), do: ShotElixir.Schticks.Schtick
  defp get_module("Weapon"), do: ShotElixir.Weapons.Weapon
  defp get_module("Faction"), do: ShotElixir.Factions.Faction
  defp get_module("Juncture"), do: ShotElixir.Junctures.Juncture
  defp get_module("Vehicle"), do: ShotElixir.Vehicles.Vehicle
  defp get_module("Site"), do: ShotElixir.Sites.Site
  defp get_module("Party"), do: ShotElixir.Parties.Party
  defp get_module("User"), do: ShotElixir.Accounts.User
  defp get_module("Fight"), do: ShotElixir.Fights.Fight
end
