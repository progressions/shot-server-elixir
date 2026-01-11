defmodule ShotElixirWeb.Api.V2.NotificationController do
  @moduledoc """
  Controller for managing user notifications.

  Provides endpoints for listing, reading, and dismissing notifications.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Notifications
  alias ShotElixir.Guardian
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns

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
  POST /api/v2/notifications

  Creates a notification for a campaign member.
  Only gamemasters can create notifications, and only for members of their current campaign.
  """
  def create(conn, %{"notification" => params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with :ok <- validate_title(params),
         :ok <- verify_gamemaster(current_user),
         {:ok, campaign} <- get_current_campaign(current_user),
         {:ok, target_user} <- get_target_user(params),
         :ok <- verify_campaign_member(campaign.id, target_user.id) do
      notification_params = %{
        user_id: target_user.id,
        type: params["type"] || "gm_announcement",
        title: params["title"],
        message: params["message"],
        payload: %{
          campaign_id: campaign.id,
          campaign_name: campaign.name,
          from_user_id: current_user.id
        }
      }

      case Notifications.create_notification(notification_params) do
        {:ok, notification} ->
          # Broadcast for real-time badge update
          Phoenix.PubSub.broadcast!(
            ShotElixir.PubSub,
            "user:#{target_user.id}",
            {:notification_created, notification}
          )

          conn
          |> put_status(:created)
          |> render(:show, notification: notification)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.ChangesetView)
          |> render(:error, changeset: changeset)
      end
    else
      {:error, :not_gamemaster} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemasters can send notifications"})

      {:error, :no_current_campaign} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No current campaign set. Use campaign set command first."})

      {:error, :user_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Target user not found"})

      {:error, :not_campaign_member} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Target user is not a member of your current campaign"})

      {:error, :title_required} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Title is required"})
    end
  end

  @doc """
  PATCH /api/v2/notifications/:id

  Updates a notification (mark as read or dismiss).
  Only allows updating read_at and dismissed_at fields for security.
  """
  def update(conn, %{"id" => id, "notification" => notification_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_user_notification(current_user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Notification not found"})

      notification ->
        # Use the user-safe update function that only allows read_at and dismissed_at
        case Notifications.update_notification_by_user(notification, notification_params) do
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

  defp validate_title(%{"title" => title}) when is_binary(title) and byte_size(title) > 0 do
    :ok
  end

  defp validate_title(_params), do: {:error, :title_required}

  defp verify_gamemaster(user) do
    if user.gamemaster do
      :ok
    else
      {:error, :not_gamemaster}
    end
  end

  defp get_current_campaign(user) do
    case user.current_campaign_id do
      nil ->
        {:error, :no_current_campaign}

      campaign_id ->
        case Campaigns.get_campaign(campaign_id) do
          nil -> {:error, :no_current_campaign}
          campaign -> {:ok, campaign}
        end
    end
  end

  defp get_target_user(%{"user_email" => email}) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_target_user(%{"user_id" => user_id}) when is_binary(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  defp get_target_user(_params), do: {:error, :user_not_found}

  defp verify_campaign_member(campaign_id, user_id) do
    campaign = Campaigns.get_campaign(campaign_id)

    cond do
      is_nil(campaign) ->
        {:error, :not_campaign_member}

      # Campaign owner (GM) is always a valid target
      campaign.user_id == user_id ->
        :ok

      # Check campaign membership table
      Campaigns.is_campaign_member?(campaign_id, user_id) ->
        :ok

      true ->
        {:error, :not_campaign_member}
    end
  end
end
