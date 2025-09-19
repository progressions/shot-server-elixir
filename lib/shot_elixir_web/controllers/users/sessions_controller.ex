defmodule ShotElixirWeb.Users.SessionsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  # POST /users/sign_in
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        # Generate JWT with claims matching Rails format
        jti = claims_jti(user)
        image_url = get_image_url(user)

        {:ok, token, _claims} = Guardian.encode_and_sign(user, %{
          "jti" => jti,
          "user" => %{
            "email" => user.email,
            "admin" => user.admin,
            "first_name" => user.first_name,
            "last_name" => user.last_name,
            "gamemaster" => user.gamemaster,
            "current_campaign" => user.current_campaign_id,
            "created_at" => DateTime.to_iso8601(user.created_at),
            "updated_at" => DateTime.to_iso8601(user.updated_at),
            "image_url" => image_url
          }
        })

        conn
        |> put_resp_header("authorization", "Bearer #{token}")
        |> put_status(:ok)
        |> json(%{
          code: 200,
          message: "User signed in successfully",
          data: render_user_data(user, jti),
          payload: %{
            jti: jti,
            user: %{
              email: user.email,
              admin: user.admin,
              first_name: user.first_name,
              last_name: user.last_name,
              gamemaster: user.gamemaster,
              current_campaign: user.current_campaign_id,
              created_at: DateTime.to_iso8601(user.created_at),
              updated_at: DateTime.to_iso8601(user.updated_at),
              image_url: image_url
            }
          }
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
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      name: user.name,
      admin: user.admin,
      gamemaster: user.gamemaster,
      current_campaign_id: user.current_campaign_id,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  defp render_user_data(user, jti) do
    %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      created_at: DateTime.to_iso8601(user.created_at),
      updated_at: DateTime.to_iso8601(user.updated_at),
      jti: jti,
      avatar_url: nil,  # TODO: implement avatar URL
      admin: user.admin,
      gamemaster: user.gamemaster,
      current_campaign_id: user.current_campaign_id,
      name: user.name,
      active: user.active,
      pending_invitation_id: nil  # TODO: implement pending invitations
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
end
