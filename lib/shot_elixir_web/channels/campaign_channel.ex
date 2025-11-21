defmodule ShotElixirWeb.CampaignChannel do
  @moduledoc """
  Channel for real-time campaign updates.
  Broadcasts changes to characters, fights, and other campaign resources.
  Rails ActionCable compatible.
  """

  use ShotElixirWeb, :channel
  require Logger

  alias ShotElixir.Campaigns

  @impl true
  def join("campaign:" <> campaign_id, _payload, socket) do
    user = socket.assigns.user

    case authorize_campaign_access(campaign_id, user) do
      :ok ->
        # Subscribe to PubSub for this campaign to receive broadcasts
        Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign_id}")

        socket = assign(socket, :campaign_id, campaign_id)
        send(self(), :after_join)

        Logger.info("User #{user.id} joined campaign:#{campaign_id}")
        {:ok, %{status: "ok"}, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    push(socket, "presence_state", %{
      user_id: socket.assigns.user_id,
      user_name: get_user_name(socket.assigns.user)
    })

    {:noreply, socket}
  end

  # Handle Rails-compatible broadcast messages from PubSub
  @impl true
  def handle_info({:rails_message, payload}, socket) do
    Logger.info("📨 CampaignChannel: Pushing message to client")
    Logger.info("Payload: #{inspect(payload)}")

    # Push to both ActionCable and Phoenix Channels clients
    # ActionCable clients expect "message" event (no event name in received callback)
    # Phoenix clients expect named events like "update"
    # For ActionCable compatibility
    push(socket, "message", payload)
    # For Phoenix Channels clients
    push(socket, "update", payload)

    Logger.info("✅ Message pushed to socket")
    {:noreply, socket}
  end

  @impl true
  def handle_in("reload", _payload, socket) do
    broadcast!(socket, "reload", %{})
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: :pong}}, socket}
  end

  # Handle character updates
  @impl true
  def handle_in("character_update", %{"character_id" => character_id}, socket) do
    broadcast!(socket, "character_update", %{
      character_id: character_id,
      updated_by: socket.assigns.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  # Handle fight updates
  @impl true
  def handle_in("fight_update", %{"fight_id" => fight_id}, socket) do
    broadcast!(socket, "fight_update", %{
      fight_id: fight_id,
      updated_by: socket.assigns.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  # Handle outgoing broadcasts - intercept and push to clients
  @impl true
  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  # Private functions

  defp authorize_campaign_access(campaign_id, user) do
    # Validate UUID format first
    case Ecto.UUID.cast(campaign_id) do
      {:ok, _uuid} ->
        case Campaigns.get_campaign(campaign_id) do
          nil ->
            {:error, "unauthorized"}

          campaign ->
            cond do
              # Campaign owner has access
              campaign.user_id == user.id ->
                :ok

              # Gamemasters and admins have access to all campaigns
              user.gamemaster || user.admin ->
                :ok

              # Players have access to campaigns they're members of
              Campaigns.is_campaign_member?(campaign_id, user.id) ->
                :ok

              true ->
                {:error, "unauthorized"}
            end
        end

      :error ->
        # Invalid UUID format
        {:error, "unauthorized"}
    end
  end

  defp get_user_name(user) do
    "#{user.first_name} #{user.last_name}"
    |> String.trim()
    |> case do
      "" -> user.email
      name -> name
    end
  end

  # Public broadcast functions for controllers

  @doc """
  Broadcasts a campaign update to all connected clients.
  """
  def broadcast_update(campaign_id, event, payload) do
    payload_with_timestamp = Map.put(payload, :timestamp, DateTime.utc_now())

    ShotElixirWeb.Endpoint.broadcast!(
      "campaign:#{campaign_id}",
      event,
      payload_with_timestamp
    )
  end

  @doc """
  Broadcasts a character change event.
  """
  def broadcast_character_change(campaign_id, character_id, action) do
    broadcast_update(campaign_id, "character_#{action}", %{
      character_id: character_id,
      action: action,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Broadcasts a fight change event.
  """
  def broadcast_fight_change(campaign_id, fight_id, action) do
    broadcast_update(campaign_id, "fight_#{action}", %{
      fight_id: fight_id,
      action: action,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Broadcasts AI image generation status (Rails ActionCable compatible format).
  Status can be 'preview_ready' with json, or 'error' with error message.
  """
  def broadcast_ai_image_status(campaign_id, status, data) do
    # Use Phoenix.PubSub for Rails-compatible broadcast
    # This will be received by handle_info({:rails_message, payload}, socket)
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign_id}",
      {:rails_message, Map.merge(%{status: status}, data)}
    )
  end
end
