defmodule ShotElixirWeb.Users.OtpController do
  @moduledoc """
  Handles OTP (One-Time Password) passwordless login.
  Supports both 6-digit codes and magic links.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  @doc """
  POST /users/otp/request
  Requests an OTP code to be sent to the user's email.
  Returns the same response whether user exists or not (prevents email enumeration).
  """
  def request(conn, %{"email" => email}) when is_binary(email) do
    # Normalize email
    email = String.downcase(String.trim(email))

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
            |> json(%{message: "If your email is in our system, you will receive a login code"})

          {:error, _changeset} ->
            conn
            |> put_status(:ok)
            |> json(%{message: "If your email is in our system, you will receive a login code"})
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

    case Accounts.verify_otp_code(email, code) do
      {:ok, user} ->
        # Clear the OTP code after successful use
        Accounts.clear_otp_code(user)

        # Generate JWT token (same pattern as sessions controller)
        {token, user_json} = generate_auth_response(user)

        conn
        |> put_resp_header("authorization", "Bearer #{token}")
        |> put_resp_header("access-control-expose-headers", "Authorization")
        |> put_status(:ok)
        |> json(%{user: user_json, token: token})

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "Code has expired. Please request a new one."})

      {:error, :invalid_code} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid code. Please check and try again."})
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

        # Generate JWT token
        {jwt_token, user_json} = generate_auth_response(user)

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

  # Private helpers - match sessions_controller.ex pattern

  defp generate_auth_response(user) do
    jti = claims_jti(user)
    image_url = get_image_url(user)
    now = System.system_time(:second)

    jwt_payload = %{
      "jti" => jti,
      "user" => %{
        "email" => user.email,
        "admin" => user.admin,
        "first_name" => user.first_name,
        "last_name" => user.last_name,
        "gamemaster" => user.gamemaster,
        "current_campaign" => user.current_campaign_id,
        "created_at" => format_datetime_rails(user.created_at),
        "updated_at" => format_datetime_rails(user.updated_at),
        "image_url" => image_url
      },
      "sub" => user.id,
      "scp" => "user",
      "aud" => nil,
      "iat" => now,
      # 7 days expiry like Rails
      "exp" => now + 7 * 24 * 60 * 60
    }

    {:ok, token, _claims} = Guardian.encode_and_sign(user, jwt_payload)

    user_json = %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      created_at: NaiveDateTime.to_iso8601(user.created_at),
      updated_at: NaiveDateTime.to_iso8601(user.updated_at),
      avatar_url: nil,
      admin: user.admin,
      gamemaster: user.gamemaster,
      current_campaign_id: user.current_campaign_id,
      name: user.name,
      active: user.active,
      pending_invitation_id: nil
    }

    {token, user_json}
  end

  defp claims_jti(user) do
    case user.email do
      "progressions@gmail.com" -> "db9f2e51-6146-4166-9e74-7adbaf1a7209"
      _ -> Ecto.UUID.generate()
    end
  end

  defp get_image_url(user) do
    case user.email do
      "progressions@gmail.com" ->
        "https://ik.imagekit.io/nvqgwnjgv/chi-war-development/DALL_E_2023-10-24_14.26.08_-_Illustration_of_Hang_Choi__a_Hong_Kong_butcher_with_a_fierce_gaze__set_against_a_solid_black_background._His_apron_is_covered_in_red_jelly__and_he_fir_cYKKk5iHY.png"

      _ ->
        Map.get(user, :image_url)
    end
  end

  defp format_datetime_rails(datetime) do
    datetime
    |> NaiveDateTime.to_string()
    |> String.replace("T", " ")
    |> Kernel.<>(" UTC")
  end
end
