defmodule ShotElixir.Services.AiCreditNotificationService do
  @moduledoc """
  Service for handling AI provider credit exhaustion notifications.

  When any AI provider (Grok, OpenAI, Gemini) returns an error indicating credits are exhausted:
  1. Updates the campaign's credit exhaustion timestamp and provider
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

  Updates the campaign's exhaustion timestamp and provider, optionally sends an email
  notification (if cooldown period has passed), and broadcasts to WebSocket.

  ## Parameters
    - campaign_id: The campaign ID
    - user_id: The user who triggered the action
    - provider: The AI provider that exhausted credits ("grok", "openai", "gemini")

  ## Returns
    - {:ok, :handled} on success (notification sent or within cooldown)
    - {:error, reason} on failure
  """
  def handle_credit_exhaustion(campaign_id, user_id, provider) do
    Logger.warning(
      "[AiCreditNotificationService] Handling #{provider} credit exhaustion for campaign #{campaign_id}"
    )

    with {:ok, campaign} <- get_campaign(campaign_id),
         {:ok, updated_campaign} <- update_exhaustion_timestamp(campaign, provider) do
      # Use atomic check-and-set to prevent race condition
      # Only one worker will successfully claim the notification slot
      notification_result =
        case try_claim_notification_slot(campaign_id) do
          {:ok, :claimed} ->
            case send_notification_email(updated_campaign, user_id, provider) do
              :ok ->
                Logger.info(
                  "[AiCreditNotificationService] Notification sent for campaign #{campaign_id} (#{provider})"
                )

                :ok

              {:error, reason} = error ->
                Logger.error(
                  "[AiCreditNotificationService] Failed to send notification for campaign #{campaign_id} (#{provider}): #{inspect(reason)}"
                )

                error
            end

          {:ok, :cooldown} ->
            Logger.info(
              "[AiCreditNotificationService] Within cooldown period for campaign #{campaign_id}"
            )

            :ok
        end

      # Broadcast to WebSocket regardless of notification result
      broadcast_credit_status(updated_campaign, provider)

      case notification_result do
        {:error, _reason} = error -> error
        _ -> {:ok, :handled}
      end
    end
  end

  @doc """
  Checks if a campaign's credits are currently marked as exhausted.
  Returns true if exhausted within the last 24 hours.
  """
  def credits_exhausted?(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil -> false
      campaign -> Campaign.ai_credits_exhausted?(campaign)
    end
  end

  @doc """
  Returns the provider that exhausted credits, or nil if not exhausted.
  """
  def exhausted_provider(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil ->
        nil

      campaign ->
        if Campaign.ai_credits_exhausted?(campaign) do
          campaign.ai_credits_exhausted_provider
        else
          nil
        end
    end
  end

  # Private functions

  defp get_campaign(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil -> {:error, :campaign_not_found}
      campaign -> {:ok, campaign}
    end
  end

  defp update_exhaustion_timestamp(campaign, provider) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      ai_credits_exhausted_at: now,
      ai_credits_exhausted_provider: provider
    }

    campaign
    |> Ecto.Changeset.change(attrs)
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
          is_nil(c.ai_credits_exhausted_notified_at) or
            c.ai_credits_exhausted_notified_at < ^cooldown_threshold
      )
      |> Repo.update_all(set: [ai_credits_exhausted_notified_at: now])

    if count > 0 do
      {:ok, :claimed}
    else
      {:ok, :cooldown}
    end
  end

  defp send_notification_email(campaign, user_id, provider) do
    provider_name = format_provider_name(provider)

    # Queue email - timestamp already updated by try_claim_notification_slot
    job_args = %{
      "type" => "ai_credits_exhausted",
      "user_id" => user_id,
      "campaign_id" => campaign.id,
      "provider_name" => provider_name
    }

    case job_args |> EmailWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[AiCreditNotificationService] Failed to enqueue email for campaign #{campaign.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp format_provider_name("grok"), do: "Grok"
  defp format_provider_name("openai"), do: "OpenAI"
  defp format_provider_name("gemini"), do: "Gemini"

  defp format_provider_name(other) do
    Logger.warning("[AiCreditNotificationService] Unknown AI provider: #{inspect(other)}")

    other
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "Unknown"
      value -> String.capitalize(value)
    end
  end

  defp broadcast_credit_status(%Campaign{} = campaign, _provider) do
    payload = %{
      campaign: %{
        id: campaign.id,
        # Provider-agnostic fields only
        is_ai_credits_exhausted: true,
        ai_credits_exhausted_at: campaign.ai_credits_exhausted_at,
        ai_credits_exhausted_provider: campaign.ai_credits_exhausted_provider
      }
    }

    # Broadcast to campaign channel
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign.id}",
      {:campaign_broadcast, payload}
    )

    # Also broadcast to owner's user channel
    if campaign.user_id do
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "user:#{campaign.user_id}",
        {:user_broadcast, payload}
      )
    end
  end
end
