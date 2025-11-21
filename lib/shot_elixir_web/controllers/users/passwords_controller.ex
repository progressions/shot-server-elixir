defmodule ShotElixirWeb.Users.PasswordsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts

  # POST /users/password
  # Request password reset
  def create(conn, %{"email" => email}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        # Don't reveal whether user exists (prevent email enumeration)
        conn
        |> put_status(:ok)
        |> json(%{
          message: "If your email is in our system, you will receive password reset instructions"
        })

      user ->
        # Generate reset token
        {:ok, user} = Accounts.generate_reset_password_token(user)

        # Queue password reset email
        %{
          "type" => "reset_password_instructions",
          "user_id" => user.id,
          "token" => user.reset_password_token
        }
        |> ShotElixir.Workers.EmailWorker.new()
        |> Oban.insert()

        conn
        |> put_status(:ok)
        |> json(%{
          message: "If your email is in our system, you will receive password reset instructions"
        })
    end
  end

  # Handle missing email
  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing email address"})
  end

  # PUT /users/password
  # Reset password with token
  def update(conn, %{"reset_password_token" => token, "password" => password}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid or expired reset token"})

      user ->
        # Check if token is expired (24 hours)
        if token_expired?(user.reset_password_sent_at) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Reset token has expired"})
        else
          # Reset the password
          case Accounts.reset_password(user, password) do
            {:ok, user} ->
              conn
              |> put_status(:ok)
              |> json(%{
                message: "Password reset successfully",
                user: %{id: user.id, email: user.email}
              })

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{errors: translate_errors(changeset)})
          end
        end
    end
  end

  # Handle missing parameters
  def update(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing reset token or password"})
  end

  defp token_expired?(nil), do: true

  defp token_expired?(sent_at) do
    expiry_hours = 24
    expires_at = NaiveDateTime.add(sent_at, expiry_hours * 3600, :second)
    NaiveDateTime.compare(NaiveDateTime.utc_now(), expires_at) == :gt
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
