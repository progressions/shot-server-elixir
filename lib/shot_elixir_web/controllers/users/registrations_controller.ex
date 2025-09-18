defmodule ShotElixirWeb.Users.RegistrationsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  # POST /users
  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)

        conn
        |> put_resp_header("authorization", "Bearer #{token}")
        |> put_status(:created)
        |> json(%{
          user: render_user(user),
          token: token
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  # Handle missing user data
  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing user data"})
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

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end