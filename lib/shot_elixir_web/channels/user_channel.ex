defmodule ShotElixirWeb.UserChannel do
  @moduledoc """
  Personal channel for user-specific notifications.
  """

  use ShotElixirWeb, :channel

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    if socket.assigns.user_id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "Not authorized"}}
    end
  end

  @impl true
  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: :pong}}, socket}
  end
end
