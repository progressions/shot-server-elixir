defmodule ShotElixirWeb.Users.SessionsControllerTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.Accounts

  setup do
    # Create a test user
    {:ok, user} = Accounts.create_user(%{
      email: "test@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    })

    %{user: user}
  end

  describe "POST /users/sign_in" do
    test "authenticates user with valid credentials", %{conn: conn, user: user} do
      conn = post(conn, "/users/sign_in", %{
        "user" => %{
          "email" => user.email,
          "password" => "password123"
        }
      })

      response = json_response(conn, 200)
      assert response["user"]["email"] == user.email
      assert response["token"]

      # Check authorization header
      [auth_header] = get_resp_header(conn, "authorization")
      assert String.starts_with?(auth_header, "Bearer ")
    end

    test "returns error with invalid credentials", %{conn: conn} do
      conn = post(conn, "/users/sign_in", %{
        "user" => %{
          "email" => "test@example.com",
          "password" => "wrongpassword"
        }
      })

      assert json_response(conn, 401) == %{
        "error" => "Invalid email or password"
      }
    end

    test "returns error with non-existent user", %{conn: conn} do
      conn = post(conn, "/users/sign_in", %{
        "user" => %{
          "email" => "nonexistent@example.com",
          "password" => "password123"
        }
      })

      assert json_response(conn, 401) == %{
        "error" => "Invalid email or password"
      }
    end
  end

  describe "DELETE /users/sign_out" do
    test "logs out successfully", %{conn: conn, user: user} do
      {:ok, token, _} = ShotElixir.Guardian.encode_and_sign(user)

      conn = conn
             |> put_req_header("authorization", "Bearer #{token}")
             |> delete("/users/sign_out")

      assert json_response(conn, 200) == %{
        "message" => "Signed out successfully"
      }
    end
  end
end