defmodule ShotElixir.Workers.CampaignSeederWorker do
  @moduledoc """
  Background worker for seeding campaigns with content from the master template.

  This worker is queued when a new campaign is created and handles:
  - Copying schticks, weapons, factions, junctures, and characters
  - Linking associations between copied entities
  - Setting the campaign's seeded_at timestamp

  The worker runs in the :default queue with max 3 attempts.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ShotElixir.Repo
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Services.CampaignSeederService
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"campaign_id" => campaign_id}}) do
    Logger.info("[CampaignSeederWorker] Starting seeding for campaign #{campaign_id}")

    case Repo.get(Campaign, campaign_id) do
      nil ->
        Logger.error("[CampaignSeederWorker] Campaign #{campaign_id} not found")
        {:error, :campaign_not_found}

      campaign ->
        case CampaignSeederService.seed_campaign(campaign) do
          {:ok, seeded_campaign} ->
            Logger.info(
              "[CampaignSeederWorker] Successfully seeded campaign #{seeded_campaign.name}"
            )

            # Broadcast campaign reload after seeding is complete
            broadcast_campaign_reload(seeded_campaign)
            :ok

          {:error, reason} ->
            Logger.error(
              "[CampaignSeederWorker] Failed to seed campaign #{campaign_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  rescue
    e ->
      Logger.error("[CampaignSeederWorker] Exception while seeding campaign: #{inspect(e)}")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))
      reraise e, __STACKTRACE__
  end

  defp broadcast_campaign_reload(campaign) do
    # Broadcast a reload event to all connected clients viewing this campaign
    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      "campaign:#{campaign.id}",
      {:campaign_seeded, %{campaign_id: campaign.id}}
    )
  end
end
