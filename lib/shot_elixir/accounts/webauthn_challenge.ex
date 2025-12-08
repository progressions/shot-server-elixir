defmodule ShotElixir.Accounts.WebauthnChallenge do
  @moduledoc """
  Schema for storing temporary WebAuthn challenges.

  Challenges are created during registration and authentication flows
  and should be deleted after use or expiration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ShotElixir.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Challenge types
  @registration "registration"
  @authentication "authentication"

  # Challenge TTL in seconds (5 minutes)
  @challenge_ttl_seconds 300

  schema "webauthn_challenges" do
    field :challenge, :binary
    field :challenge_type, :string
    field :expires_at, :utc_datetime
    field :used, :boolean, default: false

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns the registration challenge type constant.
  """
  def registration_type, do: @registration

  @doc """
  Returns the authentication challenge type constant.
  """
  def authentication_type, do: @authentication

  @doc """
  Changeset for creating a new challenge.
  """
  def create_changeset(webauthn_challenge, attrs) do
    webauthn_challenge
    |> cast(attrs, [:user_id, :challenge, :challenge_type])
    |> validate_required([:challenge, :challenge_type])
    |> validate_inclusion(:challenge_type, [@registration, @authentication])
    |> set_expiration()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Marks a challenge as used.
  """
  def mark_used_changeset(challenge) do
    change(challenge, used: true)
  end

  @doc """
  Checks if a challenge is valid (not expired and not used).
  """
  def valid?(%__MODULE__{used: true}), do: false

  def valid?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def valid?(_), do: false

  defp set_expiration(changeset) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@challenge_ttl_seconds, :second)
      |> DateTime.truncate(:second)

    put_change(changeset, :expires_at, expires_at)
  end
end
