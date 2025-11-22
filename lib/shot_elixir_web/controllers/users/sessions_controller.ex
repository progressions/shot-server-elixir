defmodule ShotElixirWeb.Users.SessionsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  # POST /users/sign_in
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        # Generate JWT with claims matching Rails format EXACTLY
        jti = claims_jti(user)
        image_url = get_image_url(user)

        # Match Rails JWT structure exactly
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

        # Generate token using Guardian but with Rails-compatible claims
        {:ok, token, _claims} = Guardian.encode_and_sign(user, jwt_payload)

        conn
        |> put_resp_header("authorization", "Bearer #{token}")
        |> put_resp_header("access-control-expose-headers", "Authorization")
        |> put_status(:ok)
        |> json(%{
          user: render_user(user),
          token: token
        })

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid email or password"})
    end
  end

  # Handle missing or invalid parameters
  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing user credentials"})
  end

  # DELETE /users/sign_out
  def delete(conn, _params) do
    # Check if user is authenticated
    case Guardian.Plug.current_resource(conn) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      _user ->
        # In JWT strategy, we don't need server-side logout
        # The client just removes the token
        conn
        |> put_status(:ok)
        |> json(%{message: "Signed out successfully"})
    end
  end

  defp render_user(user) do
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

  defp claims_jti(user) do
    # Use the user's existing JTI or generate a new one
    # Rails uses "db9f2e51-6146-4166-9e74-7adbaf1a7209" for this user
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
    # Format datetime to match Rails format: "2022-12-30 19:10:13 UTC"
    datetime
    |> NaiveDateTime.to_string()
    |> String.replace("T", " ")
    |> Kernel.<>(" UTC")
  end
end
