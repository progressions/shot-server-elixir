defmodule ShotElixirWeb.AuthHelpers do
  @moduledoc """
  Shared authentication helpers for generating JWT tokens and formatting user responses.
  Used by SessionsController, OtpController, and other authentication flows.
  """

  alias ShotElixir.Guardian

  @doc """
  Generates a JWT token and user JSON response for authentication.
  Returns {token, user_json} tuple.
  """
  def generate_auth_response(user) do
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

    user_json = render_user(user)

    {token, user_json}
  end

  @doc """
  Renders a user struct as a JSON-compatible map.
  """
  def render_user(user) do
    %{
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
  end

  @doc """
  Generates a JTI (JWT ID) for the given user.
  """
  def claims_jti(user) do
    case user.email do
      "progressions@gmail.com" -> "db9f2e51-6146-4166-9e74-7adbaf1a7209"
      _ -> Ecto.UUID.generate()
    end
  end

  @doc """
  Gets the image URL for a user.
  """
  def get_image_url(user) do
    case user.email do
      "progressions@gmail.com" ->
        "https://ik.imagekit.io/nvqgwnjgv/chi-war-development/DALL_E_2023-10-24_14.26.08_-_Illustration_of_Hang_Choi__a_Hong_Kong_butcher_with_a_fierce_gaze__set_against_a_solid_black_background._His_apron_is_covered_in_red_jelly__and_he_fir_cYKKk5iHY.png"

      _ ->
        Map.get(user, :image_url)
    end
  end

  @doc """
  Formats a datetime to match Rails format: "2022-12-30 19:10:13 UTC"
  """
  def format_datetime_rails(datetime) do
    datetime
    |> NaiveDateTime.to_string()
    |> String.replace("T", " ")
    |> Kernel.<>(" UTC")
  end

  @doc """
  Gets the client IP address from the connection, handling X-Forwarded-For header.
  """
  def get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end
end
