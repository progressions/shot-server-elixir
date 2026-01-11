defmodule ShotElixirWeb.UserChannel do
  @moduledoc """
  Personal channel for user-specific notifications.

  Handles:
  - Campaign seeding status updates (for newly created campaigns)
  - Other user-specific broadcasts
  """

  use ShotElixirWeb, :channel
  require Logger

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.user_id == user_id do
      # Subscribe to PubSub for this user's broadcasts
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "user:#{user_id}")
      {:ok, socket}
    else
      {:error, %{reason: "Not authorized"}}
    end
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: :pong}}, socket}
  end

  # Handle user broadcasts from PubSub (e.g., seeding status updates)
  @impl true
  def handle_info({:user_broadcast, payload}, socket) do
    Logger.info("📨 UserChannel: Pushing message to client")
    Logger.info("Payload: #{inspect(payload)}")

    # Push to client - using "message" event for compatibility
    push(socket, "message", payload)
    {:noreply, socket}
  end

  # Handle notification created broadcasts from NotificationController
  @impl true
  def handle_info({:notification_created, notification}, socket) do
    Logger.info("🔔 UserChannel: Pushing notification_created to client")
    Logger.info("Notification: #{inspect(notification.id)} - #{notification.title}")

    # Push notification event to client
    push(socket, "notification_created", %{
      notification: %{
        id: notification.id,
        type: notification.type,
        title: notification.title,
        message: notification.message,
        created_at: notification.inserted_at,
        payload: notification.payload || %{}
      }
    })

    {:noreply, socket}
  end
end
