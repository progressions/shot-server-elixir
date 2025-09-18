defmodule ShotElixirWeb.Users.SessionsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  # POST /users/sign_in
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)

        conn
        |> put_resp_header("authorization", "Bearer #{token}")
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
end
