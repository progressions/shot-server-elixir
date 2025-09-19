defmodule ShotElixirWeb.CampaignChannel do
  @moduledoc """
  Channel for real-time campaign updates.
  Broadcasts changes to characters, fights, and other campaign resources.
  """

  use ShotElixirWeb, :channel

  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  @impl true
  def join("campaign:" <> campaign_id, _payload, socket) do
    user = socket.assigns.user

    case authorize_campaign_access(campaign_id, user) do
      :ok ->
        socket = assign(socket, :campaign_id, campaign_id)
        send(self(), :after_join)
        {:ok, socket}

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

  # Private functions

  defp authorize_campaign_access(campaign_id, user) do
    case Campaigns.get_campaign(campaign_id) do
      nil ->
        {:error, "Campaign not found"}

      campaign ->
        cond do
          # Gamemaster has access to all campaigns they own
          campaign.user_id == user.id ->
            :ok

          # Players have access to campaigns they're members of
          Campaigns.is_campaign_member?(campaign_id, user.id) ->
            :ok

          true ->
            {:error, "Not authorized"}
        end
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
    ShotElixirWeb.Endpoint.broadcast!(
      "campaign:#{campaign_id}",
      event,
      payload
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
end