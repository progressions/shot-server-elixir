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

  # Handle solo initiative broadcasts from PubSub
  # Dual push pattern: Push to both "message" (ActionCable compatibility) and named event
  # (Phoenix Channels). ActionCable clients expect a generic "message" event, while Phoenix
  # Channels clients can listen for specific event names.
  @impl true
  def handle_info({:solo_initiative, payload}, socket) do
    Logger.info("📨 CampaignChannel: Solo initiative received")
    Logger.info("Payload: #{inspect(payload)}")

    # Push to clients with the solo_initiative event
    push(socket, "message", %{solo_initiative: payload})
    push(socket, "solo_initiative", payload)

    Logger.info("✅ Solo initiative pushed to socket")
    {:noreply, socket}
  end

  # Handle solo NPC action broadcasts from PubSub
  @impl true
  def handle_info({:solo_npc_action, payload}, socket) do
    Logger.info("📨 CampaignChannel: Solo NPC action received")
    Logger.info("Payload: #{inspect(payload)}")

    # Push to clients with the solo_npc_action event
    push(socket, "message", %{solo_npc_action: payload})
    push(socket, "solo_npc_action", payload)

    Logger.info("✅ Solo NPC action pushed to socket")
    {:noreply, socket}
  end

  # Handle solo player action broadcasts from PubSub
  @impl true
  def handle_info({:solo_player_action, payload}, socket) do
    Logger.info("📨 CampaignChannel: Solo player action received")
    Logger.info("Payload: #{inspect(payload)}")

    # Push to clients with the solo_player_action event
    push(socket, "message", %{solo_player_action: payload})
    push(socket, "solo_player_action", payload)

    Logger.info("✅ Solo player action pushed to socket")
    {:noreply, socket}
  end

  # Handle campaign broadcast messages from PubSub
  @impl true
  def handle_info({:campaign_broadcast, payload}, socket) do
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
  Broadcasts AI image generation status.
  Status can be 'preview_ready' with json, or 'error' with error message.
  """
  def broadcast_ai_image_status(campaign_id, status, data) do
    # Use Phoenix.PubSub for campaign broadcast
    # This will be received by handle_info({:campaign_broadcast, payload}, socket)
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign_id}",
      {:campaign_broadcast, Map.merge(%{status: status}, data)}
    )
  end

  @doc """
  Broadcasts a reload signal for a specific entity type.
  Example: broadcast_entity_reload(campaign_id, "Fight") sends {fights: "reload"}
  """
  def broadcast_entity_reload(campaign_id, entity_class) do
    # Convert "Fight" to "fights", "Character" to "characters", etc.
    entity_key = pluralize_entity(entity_class) |> String.to_atom()

    # Use Phoenix.PubSub for campaign broadcast
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign_id}",
      {:campaign_broadcast, %{entity_key => "reload"}}
    )
  end

  @doc """
  Broadcasts encounter update to all clients subscribed to this campaign.
  Sends full encounter data in Rails-compatible format: {encounter: <data>}
  """
  def broadcast_encounter_update(campaign_id, fight_with_associations) do
    Logger.info(
      "🔄 WEBSOCKET: broadcast_encounter_update called for fight #{fight_with_associations.id}"
    )

    # Only broadcast if fight is active (started but not ended)
    if fight_with_associations.started_at && is_nil(fight_with_associations.ended_at) do
      Logger.info("🔄 WEBSOCKET: Fight is active, broadcasting encounter update")

      # Format encounter data using the EncounterView
      encounter_data =
        ShotElixirWeb.Api.V2.EncounterView.render("show.json", %{
          encounter: fight_with_associations
        })

      # Broadcast to campaign channel with Rails-compatible format
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "campaign:#{campaign_id}",
        {:campaign_broadcast, %{encounter: encounter_data}}
      )

      Logger.info("✅ Encounter update broadcasted to campaign:#{campaign_id}")
    else
      Logger.info(
        "🔄 WEBSOCKET: Fight is not active (started_at: #{fight_with_associations.started_at}, ended_at: #{fight_with_associations.ended_at}), skipping broadcast"
      )
    end
  end

  # Simple pluralization for common entity types
  defp pluralize_entity(entity_class) do
    base = String.downcase(entity_class)

    case base do
      "adventure" -> "adventures"
      "campaign" -> "campaigns"
      "character" -> "characters"
      "faction" -> "factions"
      "fight" -> "fights"
      "image" -> "images"
      "juncture" -> "junctures"
      "party" -> "parties"
      "schtick" -> "schticks"
      "site" -> "sites"
      "vehicle" -> "vehicles"
      "weapon" -> "weapons"
      _ -> base <> "s"
    end
  end
end
