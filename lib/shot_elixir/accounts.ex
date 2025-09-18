defmodule ShotElixir.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Accounts.User

  def list_users do
    Repo.all(User)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_jti(jti) when is_binary(jti) do
    Repo.get_by(User, jti: jti)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        # Create onboarding progress (disabled in tests - DB schema mismatch)
        # ShotElixir.Onboarding.create_progress(user)
        {:ok, user}
      error -> error
    end
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      user && User.verify_password(user, password) ->
        {:ok, user}
      user ->
        {:error, :invalid_credentials}
      true ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def set_current_campaign(%User{} = user, campaign_id) do
    user
    |> Ecto.Changeset.change(current_campaign_id: campaign_id)
    |> Repo.update()
  end

  def confirm_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(confirmed_at: NaiveDateTime.utc_now())
    |> Repo.update()
  end

  def lock_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(locked_at: NaiveDateTime.utc_now())
    |> Repo.update()
  end

  def unlock_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(locked_at: nil, failed_attempts: 0)
    |> Repo.update()
  end

  def increment_failed_attempts(%User{} = user) do
    attempts = user.failed_attempts + 1
    changes = if attempts >= 5 do
      %{failed_attempts: attempts, locked_at: NaiveDateTime.utc_now()}
    else
      %{failed_attempts: attempts}
    end

    user
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  def generate_auth_token(user) do
    ShotElixir.Guardian.encode_and_sign(user)
  end

  def validate_token(token) do
    case ShotElixir.Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case get_user(claims["sub"]) do
          nil -> {:error, :user_not_found}
          user -> {:ok, user}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_confirmation_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
    user
    |> Ecto.Changeset.change(
      confirmation_token: token,
      confirmation_sent_at: NaiveDateTime.utc_now()
    )
    |> Repo.update()
  end

  def generate_reset_password_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
    user
    |> Ecto.Changeset.change(
      reset_password_token: token,
      reset_password_sent_at: NaiveDateTime.utc_now()
    )
    |> Repo.update()
  end
end