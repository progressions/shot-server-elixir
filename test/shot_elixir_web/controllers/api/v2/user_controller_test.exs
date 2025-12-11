defmodule ShotElixirWeb.Api.V2.UserControllerTest do
  use ShotElixirWeb.ConnCase, async: false
  alias ShotElixir.Accounts
  alias ShotElixir.Guardian
  alias ShotElixir.Discord.LinkCodes

  @create_attrs %{
    email: "new@example.com",
    password: "password123",
    first_name: "New",
    last_name: "User"
  }

  @update_attrs %{
    first_name: "Updated",
    last_name: "Name"
  }

  @invalid_attrs %{email: nil, password: nil}

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    test "lists all users when authenticated as admin", %{conn: conn} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          admin: true
        })

      {:ok, _user1} =
        Accounts.create_user(%{
          email: "user1@example.com",
          password: "password123",
          first_name: "User",
          last_name: "One"
        })

      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/users")
      response = json_response(conn, 200)

      assert is_list(response["users"])
      assert length(response["users"]) >= 2
    end

    test "returns unauthorized when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/users")
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns forbidden when not admin", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "regular@example.com",
          password: "password123",
          first_name: "Regular",
          last_name: "User",
          admin: false
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/users")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end
  end

  describe "show" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "show@example.com",
          password: "password123",
          first_name: "Show",
          last_name: "User"
        })

      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      %{user: user, other_user: other_user}
    end

    test "returns user data when authenticated as self", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/users/#{user.id}")
      response = json_response(conn, 200)

      assert response["id"] == user.id
      assert response["email"] == user.email
      assert response["first_name"] == "Show"
    end

    test "returns user data when authenticated as admin", %{conn: conn, user: user} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin2@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          admin: true
        })

      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/users/#{user.id}")
      response = json_response(conn, 200)

      assert response["id"] == user.id
    end

    test "returns forbidden when accessing other user", %{
      conn: conn,
      user: user,
      other_user: other_user
    } do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/users/#{other_user.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "returns not found for invalid id", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      invalid_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/users/#{invalid_id}")
      assert json_response(conn, 404)["error"] == "Not found"
    end
  end

  describe "create" do
    @tag :skip
    test "creates user when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/users", user: @create_attrs)
      response = json_response(conn, 201)

      assert response["email"] == "new@example.com"
      assert response["first_name"] == "New"
      assert response["last_name"] == "User"
      assert response["token"]
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/users", user: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end

    test "renders error when email already taken", %{conn: conn} do
      {:ok, _} = Accounts.create_user(@create_attrs)
      conn = post(conn, ~p"/api/v2/users", user: @create_attrs)
      assert json_response(conn, 422)["errors"]["email"]
    end
  end

  describe "update" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "update@example.com",
          password: "password123",
          first_name: "Update",
          last_name: "User"
        })

      %{user: user}
    end

    test "updates user when data is valid and user is self", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = patch(conn, ~p"/api/v2/users/#{user.id}", user: @update_attrs)
      response = json_response(conn, 200)

      assert response["id"] == user.id
      assert response["first_name"] == "Updated"
      assert response["last_name"] == "Name"
    end

    test "updates user when authenticated as admin", %{conn: conn, user: user} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin3@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          admin: true
        })

      conn = authenticate(conn, admin)
      conn = patch(conn, ~p"/api/v2/users/#{user.id}", user: @update_attrs)
      response = json_response(conn, 200)

      assert response["first_name"] == "Updated"
    end

    test "returns forbidden when updating other user", %{conn: conn, user: user} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other2@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      conn = authenticate(conn, user)
      conn = patch(conn, ~p"/api/v2/users/#{other_user.id}", user: @update_attrs)
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "renders errors when data is invalid", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = patch(conn, ~p"/api/v2/users/#{user.id}", user: %{email: ""})
      assert json_response(conn, 422)["errors"]
    end
  end

  describe "delete" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "delete@example.com",
          password: "password123",
          first_name: "Delete",
          last_name: "User"
        })

      %{user: user}
    end

    test "deletes user when authenticated as self", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = delete(conn, ~p"/api/v2/users/#{user.id}")
      assert response(conn, 204)

      # Verify user is soft deleted
      deleted_user = Accounts.get_user!(user.id)
      assert deleted_user.active == false
    end

    test "deletes user when authenticated as admin", %{conn: conn, user: user} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin4@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          admin: true
        })

      conn = authenticate(conn, admin)
      conn = delete(conn, ~p"/api/v2/users/#{user.id}")
      assert response(conn, 204)
    end

    test "returns forbidden when deleting other user", %{conn: conn, user: user} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other3@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      conn = authenticate(conn, user)
      conn = delete(conn, ~p"/api/v2/users/#{other_user.id}")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end
  end

  describe "current" do
    test "returns current user when authenticated", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "current@example.com",
          password: "password123",
          first_name: "Current",
          last_name: "User"
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/users/current")
      response = json_response(conn, 200)

      assert response["id"] == user.id
      assert response["email"] == user.email
      assert response["campaigns"]
      assert response["player_campaigns"]
    end

    test "returns unauthorized when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/users/current")
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "profile" do
    test "returns user profile when authenticated", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "profile@example.com",
          password: "password123",
          first_name: "Profile",
          last_name: "User"
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/users/#{user.id}/profile")
      response = json_response(conn, 200)

      assert response["id"] == user.id
      assert response["email"] == user.email
      assert response["campaigns"]
      assert response["player_campaigns"]
    end

    test "returns forbidden when accessing other user's profile", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "user@example.com",
          password: "password123",
          first_name: "User",
          last_name: "One"
        })

      {:ok, other} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/users/#{other.id}/profile")
      assert json_response(conn, 403)["error"] == "Forbidden"
    end

    test "admin can access any user's profile", %{conn: conn} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin5@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          admin: true
        })

      {:ok, user} =
        Accounts.create_user(%{
          email: "regular5@example.com",
          password: "password123",
          first_name: "Regular",
          last_name: "User"
        })

      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/users/#{user.id}/profile")
      response = json_response(conn, 200)

      assert response["id"] == user.id
    end
  end

  describe "link_discord" do
    setup do
      # Ensure the LinkCodes agent is running (it may be started by the application)
      case Process.whereis(LinkCodes) do
        nil ->
          {:ok, _pid} = LinkCodes.start_link([])

        _pid ->
          # Agent is already running, clear its state for a fresh test
          Agent.update(LinkCodes, fn _state -> %{} end)
      end

      {:ok, user} =
        Accounts.create_user(%{
          email: "linktest@example.com",
          password: "password123",
          first_name: "Link",
          last_name: "Test"
        })

      %{user: user}
    end

    test "successfully links Discord account with valid code", %{conn: conn, user: user} do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: code})
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["message"] == "Discord account linked successfully"
      assert response["discord_username"] == discord_username

      # Verify user was updated in database
      updated_user = Accounts.get_user(user.id)
      assert updated_user.discord_id == discord_id
    end

    test "returns error for invalid code", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: "INVALID"})
      response = json_response(conn, 422)

      assert response["error"] == "Invalid link code"
    end

    test "returns error for expired code", %{conn: conn, user: user} do
      discord_id = 123_456_789_012_345_679
      discord_username = "expireduser"
      code = LinkCodes.generate(discord_id, discord_username)

      # Manually expire the code by updating its expiry time
      Agent.update(LinkCodes, fn state ->
        Map.update!(state, code, fn data ->
          %{data | expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)}
        end)
      end)

      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: code})
      response = json_response(conn, 422)

      assert response["error"] == "Link code has expired"
    end

    test "returns error when Discord account already linked to another user", %{
      conn: conn,
      user: user
    } do
      # Create another user with the Discord ID already linked
      discord_id = 123_456_789_012_345_680
      discord_username = "alreadylinked"

      {:ok, other_user} =
        Accounts.create_user(%{
          email: "otherlinked@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "Linked"
        })

      {:ok, _} = Accounts.link_discord(other_user, discord_id)

      # Generate a code with the same Discord ID
      code = LinkCodes.generate(discord_id, discord_username)

      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: code})
      response = json_response(conn, 422)

      assert response["error"] == "This Discord account is already linked to another user"
    end

    test "returns success when user already linked to same Discord account", %{
      conn: conn,
      user: user
    } do
      discord_id = 123_456_789_012_345_681
      discord_username = "sameuser"

      # Link the user first
      {:ok, _} = Accounts.link_discord(user, discord_id)

      # Generate a code with the same Discord ID
      code = LinkCodes.generate(discord_id, discord_username)

      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: code})
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["message"] == "Discord account already linked"
    end

    test "returns error when code parameter is missing", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{})
      response = json_response(conn, 400)

      assert response["error"] == "Code parameter is required"
    end

    test "returns unauthorized when not authenticated", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: "ABCDEF"})
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "code is consumed after successful link and cannot be reused", %{conn: conn, user: user} do
      discord_id = 123_456_789_012_345_682
      discord_username = "consumetest"
      code = LinkCodes.generate(discord_id, discord_username)

      conn = authenticate(conn, user)
      conn = post(conn, ~p"/api/v2/users/link_discord", %{code: code})
      assert json_response(conn, 200)["success"] == true

      # Create a new user and try to use the same code
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "tryreuse@example.com",
          password: "password123",
          first_name: "Try",
          last_name: "Reuse"
        })

      conn2 = build_conn() |> put_req_header("accept", "application/json")
      conn2 = authenticate(conn2, other_user)
      conn2 = post(conn2, ~p"/api/v2/users/link_discord", %{code: code})
      response = json_response(conn2, 422)

      assert response["error"] == "Invalid link code"
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
