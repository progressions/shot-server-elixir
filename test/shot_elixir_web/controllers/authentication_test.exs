defmodule ShotElixirWeb.AuthenticationTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  @valid_user_attrs %{
    email: "test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  }

  describe "sign_in" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      %{user: user}
    end

    test "signs in user with valid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/sign_in", %{
          user: %{
            email: user.email,
            password: "password123"
          }
        })

      response = json_response(conn, 200)
      assert response["user"]["id"] == user.id
      assert response["user"]["email"] == user.email
      assert response["token"]

      # Verify token is valid
      {:ok, validated_user} = Accounts.validate_token(response["token"])
      assert validated_user.id == user.id
    end

    test "returns error with invalid password", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/sign_in", %{
          user: %{
            email: user.email,
            password: "wrongpassword"
          }
        })

      response = json_response(conn, 401)
      assert response["error"] == "Invalid email or password"
    end

    test "returns error with non-existent email", %{conn: conn} do
      conn =
        post(conn, ~p"/users/sign_in", %{
          user: %{
            email: "nonexistent@example.com",
            password: "password123"
          }
        })

      response = json_response(conn, 401)
      assert response["error"] == "Invalid email or password"
    end

    test "returns error with missing credentials", %{conn: conn} do
      conn = post(conn, ~p"/users/sign_in", %{})
      assert json_response(conn, 400)["error"] == "Missing user credentials"
    end
  end

  describe "sign_up" do
    test "creates new user and returns token", %{conn: conn} do
      conn =
        post(conn, ~p"/users/sign_up", %{
          user: %{
            email: "newuser@example.com",
            password: "password123",
            first_name: "New",
            last_name: "User"
          }
        })

      response = json_response(conn, 201)
      assert response["user"]["email"] == "newuser@example.com"
      assert response["user"]["first_name"] == "New"
      assert response["token"]

      # Verify user was created
      user = Accounts.get_user_by_email("newuser@example.com")
      assert user
      assert user.email == "newuser@example.com"
    end

    test "returns error with invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/sign_up", %{
          user: %{
            email: "invalid-email",
            password: "short"
          }
        })

      response = json_response(conn, 422)
      assert response["errors"]
      assert response["errors"]["email"]
      assert response["errors"]["password"]
    end

    test "returns error when email is already taken", %{conn: conn} do
      {:ok, _} = Accounts.create_user(@valid_user_attrs)

      conn =
        post(conn, ~p"/users/sign_up", %{
          user: @valid_user_attrs
        })

      response = json_response(conn, 422)
      assert response["errors"]["email"]
    end

    test "returns error with missing user data", %{conn: conn} do
      conn = post(conn, ~p"/users/sign_up", %{})
      assert json_response(conn, 400)["error"] == "Missing user data"
    end
  end

  describe "sign_out" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      {:ok, token, _} = Guardian.encode_and_sign(user)
      %{user: user, token: token}
    end

    test "signs out authenticated user", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/users/sign_out")

      assert json_response(conn, 200)["message"] == "Signed out successfully"
    end

    test "returns unauthorized when not authenticated", %{conn: conn} do
      conn = delete(conn, ~p"/users/sign_out")
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "protected endpoints" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      {:ok, token, _} = Guardian.encode_and_sign(user)
      %{user: user, token: token}
    end

    test "allows access with valid token", %{conn: conn, user: user, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v2/users/current")

      response = json_response(conn, 200)
      assert response["id"] == user.id
    end

    test "denies access without token", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/users/current")
      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "denies access with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> get(~p"/api/v2/users/current")

      assert json_response(conn, 401)["error"] == "Invalid token"
    end

    test "denies access with malformed authorization header", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "InvalidFormat token")
        |> get(~p"/api/v2/users/current")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "token validation" do
    test "generates and validates JWT token", %{} do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      # Generate token
      {:ok, token, claims} = Accounts.generate_auth_token(user)
      assert is_binary(token)
      assert claims["sub"] == user.id
      assert claims["jti"] == user.jti

      # Validate token
      {:ok, validated_user} = Accounts.validate_token(token)
      assert validated_user.id == user.id
    end

    test "rejects token with invalid signature", %{} do
      {:error, _reason} = Accounts.validate_token("invalid.token.here")
    end

    test "rejects token for non-existent user", %{} do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      {:ok, token, _} = Accounts.generate_auth_token(user)

      # Delete the user
      Accounts.delete_user(user)

      # Token should still be technically valid but user is inactive
      {:ok, validated_user} = Accounts.validate_token(token)
      assert validated_user.active == false
    end
  end
end
