defmodule ShotElixirWeb.Users.OtpController do
  @moduledoc """
  Handles OTP (One-Time Password) passwordless login.
  Supports both 6-digit codes and magic links.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.RateLimiter
  alias ShotElixirWeb.AuthHelpers

  @doc """
  POST /users/otp/request
  Requests an OTP code to be sent to the user's email.
  Returns the same response whether user exists or not (prevents email enumeration).
  """
  def request(conn, %{"email" => email}) when is_binary(email) do
    # Normalize email
    email = String.downcase(String.trim(email))
    ip_address = AuthHelpers.get_client_ip(conn)

    # Check rate limits before processing
    case RateLimiter.check_otp_request_rate_limit(ip_address, email) do
      {:error, :rate_limit_exceeded} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many requests. Please try again later."})

      :ok ->
        case Accounts.get_user_by_email(email) do
          nil ->
            # Don't reveal whether user exists
            conn
            |> put_status(:ok)
            |> json(%{message: "If your email is in our system, you will receive a login code"})

          user ->
            case Accounts.generate_otp_code(user) do
              {:ok, _user, otp_code, magic_token} ->
                # Queue email with OTP code and magic link
                %{
                  "type" => "otp_login",
                  "user_id" => user.id,
                  "otp_code" => otp_code,
                  "magic_token" => magic_token
                }
                |> ShotElixir.Workers.EmailWorker.new()
                |> Oban.insert()

                conn
                |> put_status(:ok)
                |> json(%{
                  message: "If your email is in our system, you will receive a login code"
                })

              {:error, _changeset} ->
                conn
                |> put_status(:ok)
                |> json(%{
                  message: "If your email is in our system, you will receive a login code"
                })
            end
        end
    end
  end

  def request(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Email is required"})
  end

  @doc """
  POST /users/otp/verify
  Verifies an OTP code and returns a JWT token on success.
  """
  def verify(conn, %{"email" => email, "code" => code})
      when is_binary(email) and is_binary(code) do
    email = String.downcase(String.trim(email))
    code = String.trim(code)
    ip_address = AuthHelpers.get_client_ip(conn)

    # Check rate limits before processing
    case RateLimiter.check_otp_verify_rate_limit(ip_address, email) do
      {:error, :rate_limit_exceeded} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many verification attempts. Please try again later."})

      :ok ->
        case Accounts.verify_otp_code(email, code) do
          {:ok, user} ->
            # Clear the OTP code and failed attempts after successful use
            Accounts.clear_otp_code(user)
            RateLimiter.clear_otp_failed_attempts(email)

            # Generate JWT token using shared helper
            {token, user_json} = AuthHelpers.generate_auth_response(user)

            conn
            |> put_resp_header("authorization", "Bearer #{token}")
            |> put_resp_header("access-control-expose-headers", "Authorization")
            |> put_status(:ok)
            |> json(%{user: user_json, token: token})

          {:error, reason} when reason in [:expired, :invalid_code] ->
            # Track failed attempt after failed verification
            case RateLimiter.track_otp_failed_attempt(email) do
              {:error, :max_attempts_exceeded} ->
                # Invalidate the OTP after too many failed attempts
                case Accounts.get_user_by_email(email) do
                  nil -> :ok
                  user -> Accounts.clear_otp_code(user)
                end

                conn
                |> put_status(:too_many_requests)
                |> json(%{error: "Too many failed attempts. Please request a new code."})

              :ok ->
                # Return uniform error to prevent email enumeration via timing/response differences
                conn
                |> put_status(:unauthorized)
                |> json(%{error: "Invalid or expired code. Please check and try again."})
            end
        end
    end
  end

  def verify(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Email and code are required"})
  end

  @doc """
  GET /users/otp/magic/:token
  Verifies a magic link token and returns a JWT token on success.
  """
  def magic_link(conn, %{"token" => token}) when is_binary(token) do
    case Accounts.verify_magic_token(token) do
      {:ok, user} ->
        # Clear the OTP code after successful use
        Accounts.clear_otp_code(user)

        # Generate JWT token using shared helper
        {jwt_token, user_json} = AuthHelpers.generate_auth_response(user)

        conn
        |> put_resp_header("authorization", "Bearer #{jwt_token}")
        |> put_resp_header("access-control-expose-headers", "Authorization")
        |> put_status(:ok)
        |> json(%{user: user_json, token: jwt_token})

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "Link has expired. Please request a new one."})

      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired link"})
    end
  end

  def magic_link(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Token is required"})
  end
end
