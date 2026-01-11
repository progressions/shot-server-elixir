defmodule ShotElixirWeb.Api.V2.NotificationControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Accounts, Notifications}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        email: "notify_test@test.com",
        password: "password123",
        first_name: "Notify",
        last_name: "User"
      })

    {:ok, other_user} =
      Accounts.create_user(%{
        email: "other@test.com",
        password: "password123",
        first_name: "Other",
        last_name: "User"
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> authenticate(user)

    %{conn: conn, user: user, other_user: other_user}
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists notifications for current user", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test Notification",
          message: "Test message"
        })

      conn = get(conn, ~p"/api/v2/notifications")
      assert %{"notifications" => [returned]} = json_response(conn, 200)
      assert returned["id"] == notification.id
      assert returned["title"] == "Test Notification"
    end

    test "does not include other user's notifications", %{
      conn: conn,
      user: user,
      other_user: other_user
    } do
      {:ok, _own_notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Own Notification"
        })

      {:ok, _other_notification} =
        Notifications.create_notification(%{
          user_id: other_user.id,
          type: "test",
          title: "Other Notification"
        })

      conn = get(conn, ~p"/api/v2/notifications")
      assert %{"notifications" => notifications} = json_response(conn, 200)
      assert length(notifications) == 1
      assert hd(notifications)["title"] == "Own Notification"
    end

    test "does not include dismissed notifications", %{conn: conn, user: user} do
      {:ok, active} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Active Notification"
        })

      {:ok, dismissed} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Dismissed Notification",
          dismissed_at: DateTime.utc_now()
        })

      conn = get(conn, ~p"/api/v2/notifications")
      assert %{"notifications" => notifications} = json_response(conn, 200)
      assert length(notifications) == 1
      assert hd(notifications)["id"] == active.id
    end

    test "filters by unread status", %{conn: conn, user: user} do
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

      conn = get(conn, ~p"/api/v2/notifications", status: "unread")
      assert %{"notifications" => notifications} = json_response(conn, 200)
      assert length(notifications) == 1
      assert hd(notifications)["id"] == unread.id
    end
  end

  describe "show" do
    test "returns notification when found", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test Notification"
        })

      conn = get(conn, ~p"/api/v2/notifications/#{notification.id}")
      assert returned = json_response(conn, 200)
      assert returned["id"] == notification.id
    end

    test "returns 404 for other user's notification", %{conn: conn, other_user: other_user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: other_user.id,
          type: "test",
          title: "Other's Notification"
        })

      conn = get(conn, ~p"/api/v2/notifications/#{notification.id}")
      assert %{"error" => "Notification not found"} = json_response(conn, 404)
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notifications/#{Ecto.UUID.generate()}")
      assert %{"error" => "Notification not found"} = json_response(conn, 404)
    end
  end

  describe "update" do
    test "marks notification as read", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test Notification"
        })

      now = DateTime.utc_now() |> DateTime.to_iso8601()

      conn =
        patch(conn, ~p"/api/v2/notifications/#{notification.id}", notification: %{read_at: now})

      assert returned = json_response(conn, 200)
      assert returned["read_at"] != nil
    end

    test "dismisses notification", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test Notification"
        })

      now = DateTime.utc_now() |> DateTime.to_iso8601()

      conn =
        patch(conn, ~p"/api/v2/notifications/#{notification.id}",
          notification: %{dismissed_at: now}
        )

      assert returned = json_response(conn, 200)
      assert returned["dismissed_at"] != nil
    end

    test "cannot modify notification type (security)", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "original_type",
          title: "Test Notification"
        })

      conn =
        patch(conn, ~p"/api/v2/notifications/#{notification.id}",
          notification: %{type: "hacked_type"}
        )

      # Update should succeed but type should be unchanged
      assert returned = json_response(conn, 200)
      assert returned["type"] == "original_type"
    end

    test "cannot modify notification title (security)", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Original Title"
        })

      conn =
        patch(conn, ~p"/api/v2/notifications/#{notification.id}",
          notification: %{title: "Hacked Title"}
        )

      # Update should succeed but title should be unchanged
      assert returned = json_response(conn, 200)
      assert returned["title"] == "Original Title"
    end

    test "cannot modify other user's notification", %{conn: conn, other_user: other_user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: other_user.id,
          type: "test",
          title: "Other's Notification"
        })

      conn =
        patch(conn, ~p"/api/v2/notifications/#{notification.id}",
          notification: %{read_at: DateTime.utc_now() |> DateTime.to_iso8601()}
        )

      assert %{"error" => "Notification not found"} = json_response(conn, 404)
    end
  end

  describe "delete" do
    test "deletes notification", %{conn: conn, user: user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Test Notification"
        })

      conn = delete(conn, ~p"/api/v2/notifications/#{notification.id}")
      assert response(conn, 204)

      assert Notifications.get_notification(notification.id) == nil
    end

    test "cannot delete other user's notification", %{conn: conn, other_user: other_user} do
      {:ok, notification} =
        Notifications.create_notification(%{
          user_id: other_user.id,
          type: "test",
          title: "Other's Notification"
        })

      conn = delete(conn, ~p"/api/v2/notifications/#{notification.id}")
      assert %{"error" => "Notification not found"} = json_response(conn, 404)
    end
  end

  describe "unread_count" do
    test "returns count of unread notifications", %{conn: conn, user: user} do
      # Create 3 unread notifications
      for i <- 1..3 do
        {:ok, _} =
          Notifications.create_notification(%{
            user_id: user.id,
            type: "test",
            title: "Notification #{i}"
          })
      end

      # Create 1 read notification
      {:ok, _} =
        Notifications.create_notification(%{
          user_id: user.id,
          type: "test",
          title: "Read Notification",
          read_at: DateTime.utc_now()
        })

      conn = get(conn, ~p"/api/v2/notifications/unread_count")
      assert %{"unread_count" => 3} = json_response(conn, 200)
    end

    test "excludes dismissed notifications", %{conn: conn, user: user} do
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

      conn = get(conn, ~p"/api/v2/notifications/unread_count")
      assert %{"unread_count" => 1} = json_response(conn, 200)
    end
  end

  describe "dismiss_all" do
    test "dismisses all notifications for user", %{conn: conn, user: user, other_user: other_user} do
      for i <- 1..3 do
        {:ok, _} =
          Notifications.create_notification(%{
            user_id: user.id,
            type: "test",
            title: "Notification #{i}"
          })
      end

      # Other user's notification should not be affected
      {:ok, other_notification} =
        Notifications.create_notification(%{
          user_id: other_user.id,
          type: "test",
          title: "Other's Notification"
        })

      conn = post(conn, ~p"/api/v2/notifications/dismiss_all")
      assert %{"dismissed_count" => 3} = json_response(conn, 200)

      # Verify all user's notifications are dismissed
      assert Notifications.unread_count(user) == 0

      # Verify other user's notification is untouched
      other_notification = Notifications.get_notification(other_notification.id)
      assert other_notification.dismissed_at == nil
    end
  end

  describe "create" do
    alias ShotElixir.Campaigns

    setup %{user: user, other_user: other_user} do
      # Create a gamemaster user
      {:ok, gm_user} =
        Accounts.create_user(%{
          email: "gamemaster@test.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      # Create a campaign owned by the gamemaster
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: gm_user.id
        })

      # Add the target user as a campaign member
      {:ok, _membership} = Campaigns.add_member(campaign, other_user)

      # Set the GM's current campaign
      {:ok, gm_user} = Accounts.update_user(gm_user, %{current_campaign_id: campaign.id})

      %{gm_user: gm_user, campaign: campaign}
    end

    test "gamemaster can send notification to campaign member", %{
      conn: conn,
      gm_user: gm_user,
      other_user: other_user
    } do
      conn =
        conn
        |> authenticate(gm_user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: other_user.email,
            title: "Session Tonight",
            message: "Game starts at 7pm!"
          }
        })

      assert returned = json_response(conn, 201)
      assert returned["title"] == "Session Tonight"
      assert returned["message"] == "Game starts at 7pm!"
      assert returned["type"] == "gm_announcement"
    end

    test "gamemaster can send notification to themselves (campaign owner)", %{
      conn: conn,
      gm_user: gm_user
    } do
      conn =
        conn
        |> authenticate(gm_user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: gm_user.email,
            title: "Self Reminder"
          }
        })

      assert returned = json_response(conn, 201)
      assert returned["title"] == "Self Reminder"
    end

    test "non-gamemaster cannot send notifications", %{
      conn: conn,
      user: user,
      other_user: other_user
    } do
      # Regular user (not gamemaster) tries to send notification
      conn =
        conn
        |> authenticate(user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: other_user.email,
            title: "Test"
          }
        })

      assert %{"error" => "Only gamemasters can send notifications"} = json_response(conn, 403)
    end

    test "returns 400 when gamemaster has no current campaign", %{conn: conn} do
      # Create a GM without a current campaign set
      {:ok, gm_no_campaign} =
        Accounts.create_user(%{
          email: "gm_no_campaign@test.com",
          password: "password123",
          first_name: "No",
          last_name: "Campaign",
          gamemaster: true
        })

      conn =
        conn
        |> authenticate(gm_no_campaign)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: "someone@test.com",
            title: "Test"
          }
        })

      assert %{"error" => "No current campaign set" <> _} = json_response(conn, 400)
    end

    test "returns 404 when target user not found", %{conn: conn, gm_user: gm_user} do
      conn =
        conn
        |> authenticate(gm_user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: "nonexistent@test.com",
            title: "Test"
          }
        })

      assert %{"error" => "Target user not found"} = json_response(conn, 404)
    end

    test "returns 403 when target is not a campaign member", %{conn: conn, gm_user: gm_user} do
      # Create a user who is not a member of the campaign
      {:ok, non_member} =
        Accounts.create_user(%{
          email: "non_member@test.com",
          password: "password123",
          first_name: "Non",
          last_name: "Member"
        })

      conn =
        conn
        |> authenticate(gm_user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: non_member.email,
            title: "Test"
          }
        })

      assert %{"error" => "Target user is not a member of your current campaign"} =
               json_response(conn, 403)
    end

    test "returns 400 when title is missing", %{
      conn: conn,
      gm_user: gm_user,
      other_user: other_user
    } do
      conn =
        conn
        |> authenticate(gm_user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: other_user.email,
            message: "No title provided"
          }
        })

      assert %{"error" => "Title is required"} = json_response(conn, 400)
    end

    test "returns 400 when title is empty string", %{
      conn: conn,
      gm_user: gm_user,
      other_user: other_user
    } do
      conn =
        conn
        |> authenticate(gm_user)
        |> post(~p"/api/v2/notifications", %{
          notification: %{
            user_email: other_user.email,
            title: ""
          }
        })

      assert %{"error" => "Title is required"} = json_response(conn, 400)
    end
  end
end
