defmodule ShotElixirWeb.Users.SessionsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian
  alias ShotElixirWeb.AuthHelpers

  # POST /users/sign_in
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        # Generate JWT token using shared helper
        {token, _user_json} = AuthHelpers.generate_auth_response(user)

        conn
        |> put_resp_header("authorization", "Bearer #{token}")
        |> put_resp_header("access-control-expose-headers", "Authorization")
        |> put_status(:ok)
        |> json(%{
          user: AuthHelpers.render_user(user),
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
end
