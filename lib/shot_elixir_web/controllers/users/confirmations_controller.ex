defmodule ShotElixirWeb.Users.ConfirmationsController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts

  # POST /users/confirm
  def create(conn, %{"confirmation_token" => token}) do
    case Accounts.get_user_by_confirmation_token(token) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invalid or expired confirmation token"})

      user ->
        # Check if token is expired (24 hours)
        if token_expired?(user.confirmation_sent_at) do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Confirmation token has expired"})
        else
          # Confirm the user and send welcome email
          {:ok, user} = Accounts.confirm_user(user)

          # Queue welcome email
          %{
            "type" => "welcome",
            "user_id" => user.id
          }
          |> ShotElixir.Workers.EmailWorker.new()
          |> Oban.insert()

          conn
          |> put_status(:ok)
          |> json(%{
            message: "Email confirmed successfully",
            user: %{
              id: user.id,
              email: user.email,
              confirmed: true
            }
          })
        end
    end
  end

  # Handle missing token
  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing confirmation token"})
  end

  defp token_expired?(nil), do: true

  defp token_expired?(sent_at) do
    expiry_hours = 24
    expires_at = NaiveDateTime.add(sent_at, expiry_hours * 3600, :second)
    NaiveDateTime.compare(NaiveDateTime.utc_now(), expires_at) == :gt
  end
end
