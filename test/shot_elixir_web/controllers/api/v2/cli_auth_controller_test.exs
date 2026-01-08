defmodule ShotElixirWeb.Api.V2.CliAuthControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian
  alias ShotElixir.RateLimiter

  @valid_user_attrs %{
    email: "cli-auth-test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  }

  defp create_user_and_token(attrs \\ %{}) do
    user_attrs = Map.merge(@valid_user_attrs, attrs)
    {:ok, user} = Accounts.create_user(user_attrs)
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {user, token}
  end

  defp authenticated_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  setup do
    # Clear rate limits before each test
    RateLimiter.clear_cli_auth_rate_limits()
    :ok
  end

  describe "POST /api/v2/cli/auth/start" do
    test "returns a code and URL", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/cli/auth/start")

      response = json_response(conn, 200)

      assert response["code"]
      assert String.length(response["code"]) == 32
      assert response["url"] =~ "/cli/auth?code="
      assert response["expires_in"] > 0
    end

    test "generates unique codes on each call", %{conn: conn} do
      conn1 = post(conn, ~p"/api/v2/cli/auth/start")
      conn2 = post(conn, ~p"/api/v2/cli/auth/start")

      response1 = json_response(conn1, 200)
      response2 = json_response(conn2, 200)

      refute response1["code"] == response2["code"]
    end

    test "returns 429 when rate limit exceeded", %{conn: conn} do
      # Exhaust the rate limit (10 requests per hour)
      for _ <- 1..10 do
        post(conn, ~p"/api/v2/cli/auth/start")
      end

      conn = post(conn, ~p"/api/v2/cli/auth/start")
      response = json_response(conn, 429)

      assert response["error"] =~ "Too many requests"
    end
  end

  describe "POST /api/v2/cli/auth/poll" do
    test "returns pending status for unapproved code", %{conn: conn} do
      {:ok, auth_code} = Accounts.create_cli_auth_code()

      conn = post(conn, ~p"/api/v2/cli/auth/poll", %{code: auth_code.code})

      response = json_response(conn, 200)

      assert response["status"] == "pending"
      assert response["expires_in"] > 0
    end

    test "returns approved status with token when approved", %{conn: conn} do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {user, _token} = create_user_and_token()

      {:ok, _} = Accounts.approve_cli_auth_code(auth_code.code, user)

      conn = post(conn, ~p"/api/v2/cli/auth/poll", %{code: auth_code.code})

      response = json_response(conn, 200)

      assert response["status"] == "approved"
      assert response["token"]
      assert response["user"]["id"] == user.id
      assert response["user"]["email"] == user.email
    end

    test "returns expired status for invalid code", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/cli/auth/poll", %{code: "nonexistent"})

      response = json_response(conn, 410)

      assert response["status"] == "expired"
      assert response["error"] =~ "expired"
    end

    test "returns 400 when code parameter is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/cli/auth/poll", %{})

      response = json_response(conn, 400)

      assert response["error"] =~ "Missing code"
    end

    test "returns 429 when rate limit exceeded", %{conn: conn} do
      {:ok, auth_code} = Accounts.create_cli_auth_code()

      # Exhaust the rate limit (30 requests per code per minute)
      for _ <- 1..30 do
        post(conn, ~p"/api/v2/cli/auth/poll", %{code: auth_code.code})
      end

      conn = post(conn, ~p"/api/v2/cli/auth/poll", %{code: auth_code.code})
      response = json_response(conn, 429)

      assert response["error"] =~ "Too many requests"
    end
  end

  describe "POST /api/v2/cli/auth/approve" do
    test "approves a valid code when authenticated", %{conn: conn} do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/cli/auth/approve", %{code: auth_code.code})

      response = json_response(conn, 200)

      assert response["success"] == true
    end

    test "returns 404 for invalid code", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/cli/auth/approve", %{code: "nonexistent"})

      response = json_response(conn, 404)

      assert response["error"] =~ "not found"
    end

    test "returns 409 when code already approved", %{conn: conn} do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {user, token} = create_user_and_token()

      # First approval
      {:ok, _} = Accounts.approve_cli_auth_code(auth_code.code, user)

      # Try to approve again
      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/cli/auth/approve", %{code: auth_code.code})

      response = json_response(conn, 409)

      assert response["error"] =~ "already approved"
    end

    test "returns 400 when code parameter is missing", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/cli/auth/approve", %{})

      response = json_response(conn, 400)

      assert response["error"] =~ "Missing code"
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      {:ok, auth_code} = Accounts.create_cli_auth_code()

      conn = post(conn, ~p"/api/v2/cli/auth/approve", %{code: auth_code.code})

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "full authorization flow" do
    test "complete flow from start to approved", %{conn: conn} do
      # Step 1: Start authorization
      start_conn = post(conn, ~p"/api/v2/cli/auth/start")
      start_response = json_response(start_conn, 200)
      code = start_response["code"]

      # Step 2: Poll (should be pending)
      poll_conn = post(conn, ~p"/api/v2/cli/auth/poll", %{code: code})
      poll_response = json_response(poll_conn, 200)
      assert poll_response["status"] == "pending"

      # Step 3: User approves in browser
      {_user, token} = create_user_and_token()

      approve_conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/cli/auth/approve", %{code: code})

      approve_response = json_response(approve_conn, 200)
      assert approve_response["success"] == true

      # Step 4: Poll again (should be approved)
      final_conn = post(conn, ~p"/api/v2/cli/auth/poll", %{code: code})
      final_response = json_response(final_conn, 200)

      assert final_response["status"] == "approved"
      assert final_response["token"]
      assert final_response["user"]
    end
  end
end
