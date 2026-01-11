defmodule ShotElixirWeb.Api.V2.NotificationView do
  @moduledoc """
  View for rendering notification responses.
  """

  def render("index.json", %{notifications: notifications, meta: meta}) do
    %{
      notifications: Enum.map(notifications, &render_notification/1),
      meta: meta
    }
  end

  def render("index.json", %{notifications: notifications}) do
    %{notifications: Enum.map(notifications, &render_notification/1)}
  end

  def render("show.json", %{notification: notification}) do
    render_notification(notification)
  end

  defp render_notification(notification) do
    %{
      id: notification.id,
      type: notification.type,
      title: notification.title,
      message: notification.message,
      payload: notification.payload,
      read_at: notification.read_at,
      dismissed_at: notification.dismissed_at,
      created_at: notification.inserted_at,
      updated_at: notification.updated_at
    }
  end
end
