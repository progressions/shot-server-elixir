defmodule ShotElixirWeb.Api.V2.UserControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

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

      assert response["user"]["id"] == user.id
      assert response["user"]["email"] == user.email
      assert response["user"]["first_name"] == "Show"
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

      assert response["user"]["id"] == user.id
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
    test "creates user when data is valid", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/users", user: @create_attrs)
      response = json_response(conn, 201)

      assert response["user"]["email"] == "new@example.com"
      assert response["user"]["first_name"] == "New"
      assert response["user"]["last_name"] == "User"
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

      assert response["user"]["id"] == user.id
      assert response["user"]["first_name"] == "Updated"
      assert response["user"]["last_name"] == "Name"
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

      assert response["user"]["first_name"] == "Updated"
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

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
