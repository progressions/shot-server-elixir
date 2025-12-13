defmodule ShotElixir.Services.GrokCreditNotificationService do
  @moduledoc """
  Service for handling Grok API credit exhaustion notifications.

  When Grok API returns a 429 error indicating credits are exhausted:
  1. Updates the campaign's credit exhaustion timestamp
  2. Sends email notification to the user (with rate limiting)
  3. Broadcasts to WebSocket so UI can show warning

  Notifications are rate-limited to once per 24 hours per campaign.
  """

  alias ShotElixir.Repo
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Workers.EmailWorker
  require Logger

  @notification_cooldown_hours 24

  @doc """
  Handles credit exhaustion for a campaign.

  Updates the campaign's exhaustion timestamp, optionally sends an email
  notification (if cooldown period has passed), and broadcasts to WebSocket.

  ## Parameters
    - campaign_id: The campaign ID
    - user_id: The user who triggered the action

  ## Returns
    - {:ok, :notified} if notification was sent
    - {:ok, :cooldown} if within cooldown period
    - {:error, reason} on failure
  """
  def handle_credit_exhaustion(campaign_id, user_id) do
    Logger.warning(
      "[GrokCreditNotificationService] Handling credit exhaustion for campaign #{campaign_id}"
    )

    with {:ok, campaign} <- get_campaign(campaign_id),
         {:ok, updated_campaign} <- update_exhaustion_timestamp(campaign) do
      # Use atomic check-and-set to prevent race condition
      # Only one worker will successfully claim the notification slot
      case try_claim_notification_slot(campaign_id) do
        {:ok, :claimed} ->
          send_notification_email(updated_campaign, user_id)

          Logger.info(
            "[GrokCreditNotificationService] Notification sent for campaign #{campaign_id}"
          )

        {:ok, :cooldown} ->
          Logger.info(
            "[GrokCreditNotificationService] Within cooldown period for campaign #{campaign_id}"
          )
      end

      # Broadcast to WebSocket regardless of notification
      broadcast_credit_status(campaign_id, updated_campaign.user_id)

      {:ok, :handled}
    end
  end

  @doc """
  Checks if a campaign's credits are currently marked as exhausted.
  Returns true if exhausted within the last 24 hours.
  """
  def credits_exhausted?(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil -> false
      campaign -> Campaign.grok_credits_exhausted?(campaign)
    end
  end

  # Private functions

  defp get_campaign(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil -> {:error, :campaign_not_found}
      campaign -> {:ok, campaign}
    end
  end

  defp update_exhaustion_timestamp(campaign) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    campaign
    |> Ecto.Changeset.change(%{grok_credits_exhausted_at: now})
    |> Repo.update()
  end

  # Atomic check-and-set to prevent race condition when multiple workers
  # hit credit exhaustion simultaneously. Only one will successfully update
  # the notified_at timestamp and send the email.
  defp try_claim_notification_slot(campaign_id) do
    import Ecto.Query

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cooldown_threshold = DateTime.add(now, -@notification_cooldown_hours, :hour)

    # Atomic update: only update if notified_at is NULL or older than cooldown period
    # This ensures only one concurrent caller can "claim" the notification slot
    {count, _} =
      from(c in Campaign,
        where: c.id == ^campaign_id,
        where:
          is_nil(c.grok_credits_exhausted_notified_at) or
            c.grok_credits_exhausted_notified_at < ^cooldown_threshold
      )
      |> Repo.update_all(set: [grok_credits_exhausted_notified_at: now])

    if count > 0 do
      {:ok, :claimed}
    else
      {:ok, :cooldown}
    end
  end

  defp send_notification_email(campaign, user_id) do
    # Queue email - timestamp already updated by try_claim_notification_slot
    %{
      "type" => "grok_credits_exhausted",
      "user_id" => user_id,
      "campaign_id" => campaign.id
    }
    |> EmailWorker.new()
    |> Oban.insert()
  end

  defp broadcast_credit_status(campaign_id, owner_user_id) do
    payload = %{
      campaign: %{
        id: campaign_id,
        is_grok_credits_exhausted: true,
        grok_credits_exhausted_at: DateTime.utc_now()
      }
    }

    # Broadcast to campaign channel
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign_id}",
      {:campaign_broadcast, payload}
    )

    # Also broadcast to owner's user channel
    if owner_user_id do
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "user:#{owner_user_id}",
        {:user_broadcast, payload}
      )
    end
  end
end
