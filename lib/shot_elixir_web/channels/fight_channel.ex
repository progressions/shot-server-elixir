defmodule ShotElixirWeb.FightChannel do
  @moduledoc """
  Channel for real-time fight updates with user presence tracking.
  Manages shot counter changes, character actions, and user presence in fights.
  """

  use ShotElixirWeb, :channel
  alias ShotElixirWeb.Presence
  alias ShotElixir.Fights
  alias ShotElixir.Campaigns
  alias Phoenix.Socket.Broadcast

  require Logger

  @impl true
  def join("fight:" <> fight_id, _payload, socket) do
    user = socket.assigns.user

    case authorize_fight_access(fight_id, user) do
      {:ok, fight} ->
        send(self(), {:after_join, fight_id})

        socket =
          socket
          |> assign(:fight_id, fight_id)
          |> assign(:fight, fight)

        # Track presence
        {:ok, _} = Presence.track(socket, user.id, %{
          user_id: user.id,
          user_name: get_user_name(user),
          joined_at: DateTime.utc_now()
        })

        Logger.info("User #{user.id} joined fight:#{fight_id}")

        # Don't push during join, return the initial state
        {:ok, %{status: "ok", fight_id: fight_id}, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl true
  def handle_info({:after_join, _fight_id}, socket) do
    # Send presence state after join
    push(socket, "presence_state", Presence.list(socket))
    # Broadcast updated user list after join
    broadcast_user_list(socket)
    {:noreply, socket}
  end

  # Handle presence updates
  @impl true
  def handle_info(%Broadcast{event: "presence_diff"}, socket) do
    broadcast_user_list(socket)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    Logger.info("User #{socket.assigns.user_id} left fight:#{socket.assigns.fight_id}")
    :ok
  end

  # Shot updates
  @impl true
  def handle_in("shot_update", %{"shot_id" => shot_id, "updates" => updates}, socket) do
    case Fights.get_shot(shot_id) do
      nil ->
        {:reply, {:error, %{reason: "Shot not found"}}, socket}

      shot ->
        case Fights.update_shot(shot, updates) do
          {:ok, updated_shot} ->
            broadcast!(socket, "shot_updated", %{
              "shot" => serialize_shot(updated_shot),
              "updated_by" => socket.assigns.user_id
            })
            {:reply, :ok, socket}

          {:error, _changeset} ->
            {:reply, {:error, %{reason: "Update failed"}}, socket}
        end
    end
  end

  # Character actions
  @impl true
  def handle_in("character_act", %{"character_id" => character_id, "action" => action}, socket) do
    broadcast!(socket, "character_acted", %{
      "character_id" => character_id,
      "action" => action,
      "acted_by" => socket.assigns.user_id,
      "timestamp" => DateTime.utc_now()
    })
    {:reply, :ok, socket}
  end

  # Shot counter management
  @impl true
  def handle_in("advance_shot", _payload, socket) do
    fight = socket.assigns.fight

    case Fights.advance_shot_counter(fight) do
      {:ok, updated_fight} ->
        broadcast!(socket, "shot_counter_changed", %{
          shot_counter: updated_fight.sequence,
          sequence: updated_fight.sequence
        })
        {:reply, :ok, assign(socket, :fight, updated_fight)}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("reset_shot_counter", _payload, socket) do
    fight = socket.assigns.fight

    case Fights.reset_shot_counter(fight) do
      {:ok, updated_fight} ->
        broadcast!(socket, "shot_counter_changed", %{
          shot_counter: updated_fight.sequence,
          sequence: updated_fight.sequence
        })
        {:reply, :ok, assign(socket, :fight, updated_fight)}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("sync_request", _payload, socket) do
    fight = socket.assigns.fight

    {:reply, {:ok, %{
      "fight_id" => fight.id,
      "timestamp" => DateTime.utc_now()
    }}, socket}
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: :pong}}, socket}
  end

  # Private functions

  defp authorize_fight_access(fight_id, user) do
    # Validate UUID format first
    case Ecto.UUID.cast(fight_id) do
      {:ok, _uuid} ->
        case Fights.get_fight(fight_id) do
          nil ->
            {:error, "unauthorized"}

          fight ->
            case Campaigns.get_campaign(fight.campaign_id) do
              nil ->
                {:error, "unauthorized"}

              campaign ->
                cond do
                  campaign.user_id == user.id ->
                    {:ok, fight}

                  user.gamemaster || user.admin ->
                    {:ok, fight}

                  Campaigns.is_campaign_member?(campaign.id, user.id) ->
                    {:ok, fight}

                  true ->
                    {:error, "unauthorized"}
                end
            end
        end

      :error ->
        # Invalid UUID format
        {:error, "unauthorized"}
    end
  end

  defp broadcast_user_list(socket) do
    users =
      Presence.list(socket)
      |> Enum.map(fn {_user_id, %{metas: [meta | _]}} ->
        %{
          id: meta.user_id,
          name: meta.user_name,
          joined_at: meta.joined_at
        }
      end)

    broadcast!(socket, "users_updated", %{users: users})
  end

  defp get_user_name(user) do
    "#{user.first_name} #{user.last_name}"
    |> String.trim()
    |> case do
      "" -> user.email
      name -> name
    end
  end

  defp serialize_shot(shot) do
    %{
      "id" => shot.id,
      "shot_number" => shot.shot,
      "acted" => Map.get(shot, :acted, false),
      "character_id" => shot.character_id,
      "vehicle_id" => shot.vehicle_id
    }
  end

  # Public broadcast functions for controllers

  @doc """
  Broadcasts a fight update to all connected clients.
  """
  def broadcast_fight_update(fight_id, event, payload) do
    payload_with_timestamp = Map.put(payload, :timestamp, DateTime.utc_now())

    ShotElixirWeb.Endpoint.broadcast!(
      "fight:#{fight_id}",
      event,
      payload_with_timestamp
    )
  end

  @doc """
  Broadcasts shot changes.
  """
  def broadcast_shot_change(fight_id, shot_id, action) do
    broadcast_fight_update(fight_id, "shot_#{action}", %{
      shot_id: shot_id,
      action: action,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Broadcasts that the fight has been touched (updated).
  """
  def broadcast_fight_touched(fight_id) do
    broadcast_fight_update(fight_id, "fight_touched", %{
      timestamp: DateTime.utc_now()
    })
  end
end