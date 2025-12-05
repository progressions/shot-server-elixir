defmodule ShotElixirWeb.Users.OtpControllerTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.Accounts
  alias ShotElixir.RateLimiter

  setup do
    # Create a test user with a unique email per test
    unique_email = "otp_test_#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Accounts.create_user(%{
        email: unique_email,
        password: "password123",
        first_name: "OTP",
        last_name: "User"
      })

    # Clear any rate limits for this user's email
    RateLimiter.clear_otp_rate_limits(user.email)

    %{user: user}
  end

  describe "POST /users/otp/request" do
    test "returns success message for existing user", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/otp/request", email: user.email)
      response = json_response(conn, 200)

      assert response["message"] ==
               "If your email is in our system, you will receive a login code"
    end

    test "returns same success message for non-existing user (prevents enumeration)", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/users/otp/request",
          email: "nonexistent_#{System.unique_integer()}@example.com"
        )

      response = json_response(conn, 200)

      # Should return the same message to prevent email enumeration
      assert response["message"] ==
               "If your email is in our system, you will receive a login code"
    end

    test "normalizes email case", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/otp/request", email: String.upcase(user.email))
      response = json_response(conn, 200)

      assert response["message"] ==
               "If your email is in our system, you will receive a login code"
    end

    test "returns error when email is missing", %{conn: conn} do
      conn = post(conn, ~p"/users/otp/request", %{})
      assert json_response(conn, 400)["error"] == "Email is required"
    end

    test "generates OTP code for user", %{conn: conn, user: user} do
      post(conn, ~p"/users/otp/request", email: user.email)

      # Verify OTP was generated
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.reset_password_token != nil
      assert updated_user.reset_password_sent_at != nil
    end
  end

  describe "POST /users/otp/verify" do
    setup %{user: user} do
      # Generate an OTP code for the user
      {:ok, updated_user, otp_code, magic_token} = Accounts.generate_otp_code(user)
      # Clear rate limits again after OTP generation
      RateLimiter.clear_otp_rate_limits(user.email)
      %{user: updated_user, otp_code: otp_code, magic_token: magic_token}
    end

    test "authenticates user with valid OTP code", %{conn: conn, user: user, otp_code: otp_code} do
      conn = post(conn, ~p"/users/otp/verify", email: user.email, code: otp_code)
      response = json_response(conn, 200)

      assert response["user"]["email"] == user.email
      assert response["token"]

      # Check authorization header
      [auth_header] = get_resp_header(conn, "authorization")
      assert String.starts_with?(auth_header, "Bearer ")
    end

    test "returns uniform error for invalid OTP code", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/otp/verify", email: user.email, code: "000000")
      response = json_response(conn, 401)

      # Should return uniform error message (same for expired and invalid)
      assert response["error"] == "Invalid or expired code. Please check and try again."
    end

    test "returns uniform error for expired OTP code", %{
      conn: conn,
      user: user,
      otp_code: otp_code
    } do
      # Manually set the sent_at to be expired (more than 10 minutes ago)
      expired_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -11 * 60, :second)

      user
      |> Ecto.Changeset.change(reset_password_sent_at: expired_time)
      |> ShotElixir.Repo.update!()

      conn = post(conn, ~p"/users/otp/verify", email: user.email, code: otp_code)
      response = json_response(conn, 401)

      # Should return the same uniform error message
      assert response["error"] == "Invalid or expired code. Please check and try again."
    end

    test "clears OTP code after successful verification", %{
      conn: conn,
      user: user,
      otp_code: otp_code
    } do
      post(conn, ~p"/users/otp/verify", email: user.email, code: otp_code)

      # Verify OTP was cleared
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.reset_password_token == nil
      assert updated_user.reset_password_sent_at == nil
    end

    test "returns error when email is missing", %{conn: conn, otp_code: otp_code} do
      conn = post(conn, ~p"/users/otp/verify", code: otp_code)
      assert json_response(conn, 400)["error"] == "Email and code are required"
    end

    test "returns error when code is missing", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/otp/verify", email: user.email)
      assert json_response(conn, 400)["error"] == "Email and code are required"
    end

    test "normalizes email case", %{conn: conn, user: user, otp_code: otp_code} do
      conn = post(conn, ~p"/users/otp/verify", email: String.upcase(user.email), code: otp_code)
      response = json_response(conn, 200)

      assert response["user"]["email"] == user.email
    end
  end

  describe "GET /users/otp/magic/:token" do
    setup %{user: user} do
      {:ok, updated_user, _otp_code, magic_token} = Accounts.generate_otp_code(user)
      %{user: updated_user, magic_token: magic_token}
    end

    test "authenticates user with valid magic link token", %{
      conn: conn,
      user: user,
      magic_token: magic_token
    } do
      conn = get(conn, ~p"/users/otp/magic/#{magic_token}")
      response = json_response(conn, 200)

      assert response["user"]["email"] == user.email
      assert response["token"]

      # Check authorization header
      [auth_header] = get_resp_header(conn, "authorization")
      assert String.starts_with?(auth_header, "Bearer ")
    end

    test "returns error for invalid magic link token", %{conn: conn} do
      conn = get(conn, ~p"/users/otp/magic/invalid_token")
      response = json_response(conn, 401)

      assert response["error"] == "Invalid or expired link"
    end

    test "returns error for expired magic link token", %{
      conn: conn,
      user: user,
      magic_token: magic_token
    } do
      # Manually set the sent_at to be expired
      expired_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -11 * 60, :second)

      user
      |> Ecto.Changeset.change(reset_password_sent_at: expired_time)
      |> ShotElixir.Repo.update!()

      conn = get(conn, ~p"/users/otp/magic/#{magic_token}")
      response = json_response(conn, 410)

      assert response["error"] == "Link has expired. Please request a new one."
    end

    test "clears OTP code after successful magic link verification", %{
      conn: conn,
      user: user,
      magic_token: magic_token
    } do
      get(conn, ~p"/users/otp/magic/#{magic_token}")

      # Verify OTP was cleared
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.reset_password_token == nil
      assert updated_user.reset_password_sent_at == nil
    end
  end

  describe "rate limiting" do
    test "rate limits OTP requests per email", %{conn: conn, user: user} do
      # Make multiple requests to trigger rate limit
      # Rate limit is 3 per hour for email
      for _ <- 1..3 do
        post(conn, ~p"/users/otp/request", email: user.email)
      end

      # Next request should be rate limited
      conn = post(conn, ~p"/users/otp/request", email: user.email)
      response = json_response(conn, 429)

      assert response["error"] == "Too many requests. Please try again later."
    end

    test "rate limits OTP verification attempts per email", %{conn: conn, user: user} do
      # Generate OTP for the user
      {:ok, _updated_user, _otp_code, _magic_token} = Accounts.generate_otp_code(user)

      # Make multiple failed verification attempts
      # Rate limit is 5 per 10 minutes for email
      for _ <- 1..5 do
        post(conn, ~p"/users/otp/verify", email: user.email, code: "000000")
      end

      # Next request should be rate limited
      conn = post(conn, ~p"/users/otp/verify", email: user.email, code: "000000")
      response = json_response(conn, 429)

      assert response["error"] == "Too many verification attempts. Please try again later."
    end

    test "locks out after 3 failed attempts and invalidates OTP", %{conn: conn, user: user} do
      # Generate OTP for the user
      {:ok, _updated_user, _otp_code, _magic_token} = Accounts.generate_otp_code(user)

      # Make 3 failed attempts (the limit for failed attempts tracking)
      for _ <- 1..3 do
        post(conn, ~p"/users/otp/verify", email: user.email, code: "000000")
      end

      # 4th attempt should indicate too many failed attempts
      conn = post(conn, ~p"/users/otp/verify", email: user.email, code: "000000")
      response = json_response(conn, 429)

      assert response["error"] == "Too many failed attempts. Please request a new code."

      # OTP should be invalidated
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.reset_password_token == nil
    end
  end
end
