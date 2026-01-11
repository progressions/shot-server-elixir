defmodule ShotElixir.NotificationsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Notifications
  alias ShotElixir.Notifications.Notification
  alias ShotElixir.Accounts

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "notify_context_test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, other_user} =
      Accounts.create_user(%{
        email: "other_notify_test@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "User"
      })

    {:ok, user: user, other_user: other_user}
  end

  describe "create_notification/1" do
    test "creates notification with valid attributes", %{user: user} do
      attrs = %{
        user_id: user.id,
        type: "test_type",
        title: "Test Title",
        message: "Test message",
        payload: %{"key" => "value"}
      }

      assert {:ok, notification} = Notifications.create_notification(attrs)
      assert notification.user_id == user.id
      assert notification.type == "test_type"
      assert notification.title == "Test Title"
      assert notification.message == "Test message"
      assert notification.payload == %{"key" => "value"}
      assert notification.read_at == nil
      assert notification.dismissed_at == nil
    end

    test "requires type", %{user: user} do
      attrs = %{user_id: user.id, title: "Test Title"}

      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert "can't be blank" in errors_on(changeset).type
    end

    test "requires title", %{user: user} do
      attrs = %{user_id: user.id, type: "test_type"}

      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert "can't be blank" in errors_on(changeset).title
    end

    test "requires user_id" do
      attrs = %{type: "test_type", title: "Test Title"}

      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert "can't be blank" in errors_on(changeset).user_id
    end
  end

  describe "list_notifications/2" do
    test "lists notifications for user", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      notifications = Notifications.list_notifications(user)
      assert length(notifications) == 1
      assert hd(notifications).id == notification.id
    end

    test "excludes dismissed notifications", %{user: user} do
      {:ok, _dismissed} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Dismissed",
          dismissed_at: DateTime.utc_now()
        })

      {:ok, active} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Active"
        })

      notifications = Notifications.list_notifications(user)
      assert length(notifications) == 1
      assert hd(notifications).id == active.id
    end

    test "filters by unread status", %{user: user} do
      {:ok, unread} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Unread"
        })

      {:ok, _read} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Read",
          read_at: DateTime.utc_now()
        })

      notifications = Notifications.list_notifications(user, %{"status" => "unread"})
      assert length(notifications) == 1
      assert hd(notifications).id == unread.id
    end

    test "respects limit parameter", %{user: user} do
      for i <- 1..5 do
        {:ok, _} =
          Notifications.create_notification(%{
            user_id: user.id,
            type: "test",
            title: "Notification #{i}"
          })
      end

      notifications = Notifications.list_notifications(user, %{"limit" => 3})
      assert length(notifications) == 3
    end

    test "orders by inserted_at descending", %{user: user} do
      for i <- 1..3 do
        {:ok, _} =
          Notifications.create_notification(%{
            user_id: user.id,
            type: "test",
            title: "Notification #{i}"
          })
      end

      notifications = Notifications.list_notifications(user)
      assert length(notifications) == 3

      # Verify ordering: each notification's inserted_at should be >= the next one
      timestamps = Enum.map(notifications, & &1.inserted_at)
      sorted_desc = Enum.sort(timestamps, {:desc, DateTime})
      assert timestamps == sorted_desc
    end
  end

  describe "get_notification/1" do
    test "returns notification by id", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      found = Notifications.get_notification(notification.id)
      assert found.id == notification.id
    end

    test "returns nil for non-existent id" do
      assert Notifications.get_notification(Ecto.UUID.generate()) == nil
    end
  end

  describe "update_notification/2" do
    test "updates notification with valid attrs", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Original"
        })

      assert {:ok, updated} =
               Notifications.update_notification(notification, %{title: "Updated"})

      assert updated.title == "Updated"
    end
  end

  describe "update_notification_by_user/2" do
    test "allows updating read_at", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      now = DateTime.utc_now()

      assert {:ok, updated} =
               Notifications.update_notification_by_user(notification, %{read_at: now})

      assert updated.read_at != nil
    end

    test "allows updating dismissed_at", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      now = DateTime.utc_now()

      assert {:ok, updated} =
               Notifications.update_notification_by_user(notification, %{dismissed_at: now})

      assert updated.dismissed_at != nil
    end

    test "ignores attempts to update type", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "original",
          title: "Test"
        })

      assert {:ok, updated} =
               Notifications.update_notification_by_user(notification, %{type: "hacked"})

      assert updated.type == "original"
    end

    test "ignores attempts to update title", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Original Title"
        })

      assert {:ok, updated} =
               Notifications.update_notification_by_user(notification, %{title: "Hacked"})

      assert updated.title == "Original Title"
    end

    test "ignores attempts to update user_id", %{user: user, other_user: other_user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      assert {:ok, updated} =
               Notifications.update_notification_by_user(notification, %{user_id: other_user.id})

      assert updated.user_id == user.id
    end
  end

  describe "mark_as_read/1" do
    test "sets read_at to current time", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      assert notification.read_at == nil
      assert {:ok, updated} = Notifications.mark_as_read(notification)
      assert updated.read_at != nil
    end
  end

  describe "dismiss_notification/1" do
    test "sets dismissed_at to current time", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      assert notification.dismissed_at == nil
      assert {:ok, updated} = Notifications.dismiss_notification(notification)
      assert updated.dismissed_at != nil
    end
  end

  describe "dismiss_all_notifications/1" do
    test "dismisses all notifications for user", %{user: user, other_user: other_user} do
      for i <- 1..3 do
        {:ok, _} =
          Notifications.create_notification(%{
            user_id: user.id,
            type: "test",
            title: "Notification #{i}"
          })
      end

      {:ok, other_notification} =
        Notifications.create_notification(%{
          user_id: other_user.id,
          type: "test",
          title: "Other's notification"
        })

      assert {:ok, 3} = Notifications.dismiss_all_notifications(user)

      # User's notifications should be dismissed
      notifications = Notifications.list_notifications(user)
      assert notifications == []

      # Other user's notification should be untouched
      other_notification = Notifications.get_notification(other_notification.id)
      assert other_notification.dismissed_at == nil
    end

    test "does not dismiss already dismissed notifications", %{user: user} do
      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Active"
        })

      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Already Dismissed",
          dismissed_at: DateTime.utc_now()
        })

      assert {:ok, 1} = Notifications.dismiss_all_notifications(user)
    end
  end

  describe "unread_count/1" do
    test "counts unread notifications", %{user: user} do
      for i <- 1..3 do
        {:ok, _} =
          Notifications.create_notification(%{
            user_id: user.id,
            type: "test",
            title: "Unread #{i}"
          })
      end

      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Read",
          read_at: DateTime.utc_now()
        })

      assert Notifications.unread_count(user) == 3
    end

    test "excludes dismissed notifications", %{user: user} do
      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Active"
        })

      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Dismissed",
          dismissed_at: DateTime.utc_now()
        })

      assert Notifications.unread_count(user) == 1
    end

    test "returns 0 when no unread notifications", %{user: user} do
      assert Notifications.unread_count(user) == 0
    end
  end

  describe "delete_notification/1" do
    test "deletes notification", %{user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test"
        })

      assert {:ok, _deleted} = Notifications.delete_notification(notification)
      assert Notifications.get_notification(notification.id) == nil
    end
  end
end
