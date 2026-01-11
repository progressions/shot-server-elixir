defmodule ShotElixir.Notifications do
  @moduledoc """
  Context module for managing user notifications.

  Provides CRUD operations for notifications with support for
  marking as read and dismissing.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Notifications.Notification

  @doc """
  Lists notifications for a user.

  ## Options
    - status: "unread" to filter only unread notifications
    - limit: maximum number of notifications to return (default: 20)

  ## Examples

      iex> list_notifications(user)
      [%Notification{}, ...]

      iex> list_notifications(user, %{"status" => "unread"})
      [%Notification{read_at: nil}, ...]
  """
  def list_notifications(user, params \\ %{}) do
    limit = Map.get(params, "limit", 20)

    Notification
    |> where([n], n.user_id == ^user.id)
    |> where([n], is_nil(n.dismissed_at))
    |> filter_by_status(params["status"])
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp filter_by_status(query, "unread") do
    where(query, [n], is_nil(n.read_at))
  end

  defp filter_by_status(query, _), do: query

  @doc """
  Gets the count of unread notifications for a user.
  """
  def unread_count(user) do
    Notification
    |> where([n], n.user_id == ^user.id)
    |> where([n], is_nil(n.read_at))
    |> where([n], is_nil(n.dismissed_at))
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets a notification by ID.
  """
  def get_notification(id) do
    Repo.get(Notification, id)
  end

  @doc """
  Gets a notification by ID, raises if not found.
  """
  def get_notification!(id) do
    Repo.get!(Notification, id)
  end

  @doc """
  Creates a notification.

  ## Examples

      iex> create_notification(%{user_id: user_id, type: "ai_credits_exhausted", title: "Credits Exhausted"})
      {:ok, %Notification{}}
  """
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification.
  """
  def update_notification(%Notification{} = notification, attrs) do
    notification
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a notification as read.
  """
  def mark_as_read(%Notification{} = notification) do
    update_notification(notification, %{read_at: DateTime.utc_now()})
  end

  @doc """
  Dismisses a notification.
  """
  def dismiss_notification(%Notification{} = notification) do
    update_notification(notification, %{dismissed_at: DateTime.utc_now()})
  end

  @doc """
  Dismisses all notifications for a user.

  Returns the number of notifications dismissed.
  """
  def dismiss_all_notifications(user) do
    now = DateTime.utc_now()

    {count, _} =
      Notification
      |> where([n], n.user_id == ^user.id)
      |> where([n], is_nil(n.dismissed_at))
      |> Repo.update_all(set: [dismissed_at: now, updated_at: now])

    {:ok, count}
  end

  @doc """
  Deletes a notification.
  """
  def delete_notification(%Notification{} = notification) do
    Repo.delete(notification)
  end
end
