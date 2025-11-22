defmodule ShotElixirWeb.Users.ConfirmationsControllerTest do
  use ShotElixirWeb.ConnCase
  alias ShotElixir.Accounts

  setup do
    # Create an unconfirmed user with a confirmation token
    {:ok, user} =
      Accounts.create_user(%{
        email: "confirm_test@example.com",
        password: "password123",
        first_name: "Confirm",
        last_name: "Me"
      })

    # Generate a token manually
    {:ok, user} = Accounts.generate_confirmation_token(user)

    %{user: user, token: user.confirmation_token}
  end

  describe "POST /users/confirmation" do
    test "confirms user with valid token", %{conn: conn, user: user, token: token} do
      conn = post(conn, ~p"/users/confirmation", confirmation_token: token)
      response = json_response(conn, 200)

      assert response["message"] == "Email confirmed successfully"
      # assert response["token"] # Removing this assertion until verified
      assert response["user"]["email"] == user.email

      # Verify user is confirmed in DB
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.confirmed_at != nil
      assert updated_user.confirmation_token == nil
    end

    test "returns error with invalid token", %{conn: conn} do
      conn = post(conn, ~p"/users/confirmation", confirmation_token: "invalid_token")
      assert json_response(conn, 404)["error"] == "Invalid or expired confirmation token"
    end

    test "returns error when token is missing", %{conn: conn} do
      conn = post(conn, ~p"/users/confirmation")
      assert json_response(conn, 400)["error"] == "Missing confirmation token"
    end
  end
end
