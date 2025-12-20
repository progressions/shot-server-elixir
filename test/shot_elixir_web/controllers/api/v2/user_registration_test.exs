defmodule ShotElixirWeb.Api.V2.UserRegistrationTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.Accounts

  @create_attrs %{
    email: "registration_test@example.com",
    password: "password123",
    first_name: "Reg",
    last_name: "User"
  }

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "registration flow" do
    test "registers a new user and generates confirmation token", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/users/register", user: @create_attrs)
      response = json_response(conn, 201)

      assert response["data"]["email"] == @create_attrs.email

      assert response["message"] ==
               "Registration successful. Please check your email to confirm your account."

      # Fetch user to check attributes
      user = Accounts.get_user_by_email(@create_attrs.email)
      assert user
      assert user.confirmed_at == nil
      assert user.confirmation_token != nil
      # Default should be player (not gamemaster)
      assert user.gamemaster == false
    end

    test "registers a gamemaster when explicitly requested", %{conn: conn} do
      attrs = Map.put(@create_attrs, :email, "gm_test@example.com")
      conn = post(conn, ~p"/api/v2/users/register", user: Map.put(attrs, :gamemaster, true))
      response = json_response(conn, 201)

      assert response["data"]["email"] == "gm_test@example.com"

      user = Accounts.get_user_by_email("gm_test@example.com")
      assert user
      assert user.gamemaster == true
    end
  end
end
