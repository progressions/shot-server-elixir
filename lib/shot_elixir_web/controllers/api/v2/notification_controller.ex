defmodule ShotElixirWeb.Api.V2.NotificationController do
  @moduledoc """
  Controller for managing user notifications.

  Provides endpoints for listing, reading, and dismissing notifications.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Notifications
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  plug :put_view, ShotElixirWeb.Api.V2.NotificationView

  @doc """
  GET /api/v2/notifications

  Lists notifications for the current user.
  """
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    notifications = Notifications.list_notifications(current_user, params)
    render(conn, :index, notifications: notifications)
  end

  @doc """
  GET /api/v2/notifications/:id

  Shows a single notification.
  """
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_user_notification(current_user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Notification not found"})

      notification ->
        render(conn, :show, notification: notification)
    end
  end

  @doc """
  PATCH /api/v2/notifications/:id

  Updates a notification (mark as read or dismiss).
  """
  def update(conn, %{"id" => id, "notification" => notification_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_user_notification(current_user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Notification not found"})

      notification ->
        case Notifications.update_notification(notification, notification_params) do
          {:ok, updated_notification} ->
            render(conn, :show, notification: updated_notification)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(ShotElixirWeb.ChangesetView)
            |> render(:error, changeset: changeset)
        end
    end
  end

  @doc """
  DELETE /api/v2/notifications/:id

  Deletes a notification.
  """
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_user_notification(current_user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Notification not found"})

      notification ->
        case Notifications.delete_notification(notification) do
          {:ok, _deleted} ->
            send_resp(conn, :no_content, "")

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete notification"})
        end
    end
  end

  @doc """
  GET /api/v2/notifications/unread_count

  Returns the count of unread notifications.
  """
  def unread_count(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)
    count = Notifications.unread_count(current_user)
    json(conn, %{unread_count: count})
  end

  @doc """
  POST /api/v2/notifications/dismiss_all

  Dismisses all notifications for the current user.
  """
  def dismiss_all(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)
    {:ok, count} = Notifications.dismiss_all_notifications(current_user)
    json(conn, %{dismissed_count: count})
  end

  # Private helpers

  defp get_user_notification(user_id, notification_id) do
    case Notifications.get_notification(notification_id) do
      nil -> nil
      notification when notification.user_id == user_id -> notification
      _notification -> nil
    end
  end
end
