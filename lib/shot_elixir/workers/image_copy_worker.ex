defmodule ShotElixir.Workers.ImageCopyWorker do
  @moduledoc """
  Background worker for copying images between entities.

  This worker handles individual image copy operations, allowing for:
  - Independent retry logic per image
  - Parallelization of image copies
  - No blocking of database connections during HTTP requests

  The worker runs in the :images queue with max 3 attempts.
  """

  use Oban.Worker, queue: :images, max_attempts: 3

  alias ShotElixir.Services.ImageKitImporter
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "source_type" => source_type,
          "source_id" => source_id,
          "target_type" => target_type,
          "target_id" => target_id
        }
      }) do
    Logger.info(
      "[ImageCopyWorker] Copying image from #{source_type}:#{source_id} to #{target_type}:#{target_id}"
    )

    # Get the source and target entities
    with {:ok, source} <- get_entity(source_type, source_id),
         {:ok, target} <- get_entity(target_type, target_id) do
      case ImageKitImporter.copy_image(source, target) do
        {:ok, _attachment} ->
          Logger.info(
            "[ImageCopyWorker] Successfully copied image to #{target_type}:#{target_id}"
          )

          :ok

        {:error, :no_image} ->
          # Source has no image - this is fine, not an error
          Logger.debug("[ImageCopyWorker] Source #{source_type}:#{source_id} has no image")
          :ok

        {:error, reason} ->
          Logger.error(
            "[ImageCopyWorker] Failed to copy image to #{target_type}:#{target_id}: #{inspect(reason)}"
          )

          # Return error to trigger retry
          {:error, reason}
      end
    else
      {:error, :not_found} ->
        Logger.error("[ImageCopyWorker] Entity not found - discarding job")

        # Non-retryable: entity doesn't exist
        {:discard, :entity_not_found}
    end
  rescue
    e ->
      Logger.error("[ImageCopyWorker] Exception while copying image: #{inspect(e)}")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      reraise e, __STACKTRACE__
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
