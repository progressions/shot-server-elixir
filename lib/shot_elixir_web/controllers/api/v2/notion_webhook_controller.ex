defmodule ShotElixirWeb.Api.V2.NotionWebhookController do
  @moduledoc """
  Handles incoming webhook events from Notion.

  This endpoint receives real-time notifications when pages are created, updated,
  or deleted in Notion workspaces connected to Chi War campaigns.

  ## Verification Handshake

  When a webhook subscription is created in Notion, they send a POST request with
  a `verification_token`. This token must be manually entered in the Notion UI
  to verify the endpoint.

  ## Event Processing

  Events are acknowledged immediately with a 200 response and processed
  asynchronously via an Oban worker to prevent timeouts.
  """

  use ShotElixirWeb, :controller
  require Logger

  alias ShotElixir.Workers.NotionWebhookWorker

  @doc """
  Receives webhook events from Notion.

  Handles two cases:
  1. Verification handshake - returns the token for manual verification in Notion UI
  2. Event notification - queues an Oban job for async processing

  Always responds with 200 to acknowledge receipt (Notion retries on non-2xx).
  """
  def webhook(conn, %{"verification_token" => token}) do
    # Verification handshake - log the token for manual verification
    Logger.info("Notion webhook verification token received: #{token}")

    conn
    |> put_status(:ok)
    |> json(%{
      message:
        "Verification token received. Enter this token in Notion to verify the subscription.",
      verification_token: token
    })
  end

  def webhook(conn, params) do
    # Extract event metadata for logging
    event_id = params["id"]
    event_type = params["type"]
    workspace_id = params["workspace_id"]

    Logger.info(
      "Notion webhook received: event_id=#{event_id} type=#{event_type} workspace=#{workspace_id}"
    )

    # Queue for async processing with idempotency via Oban unique
    case queue_webhook_job(params) do
      {:ok, _job} ->
        Logger.debug("Notion webhook queued: event_id=#{event_id}")

      {:error, reason} ->
        # Log but still return 200 to prevent Notion retries for our errors
        Logger.error("Failed to queue Notion webhook: #{inspect(reason)}")
    end

    # Always return 200 to acknowledge receipt
    send_resp(conn, 200, "")
  end

  defp queue_webhook_job(params) do
    %{
      event_id: params["id"],
      event_type: params["type"],
      workspace_id: params["workspace_id"],
      entity_id: get_in(params, ["entity", "id"]),
      entity_type: get_in(params, ["entity", "type"]),
      timestamp: params["timestamp"],
      payload: params
    }
    |> NotionWebhookWorker.new()
    |> Oban.insert()
  end
end
