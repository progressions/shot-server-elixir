defmodule ShotElixir.Accounts.WebauthnCredential do
  @moduledoc """
  Schema for storing registered WebAuthn/passkey credentials.

  Each credential represents a single registered passkey for a user.
  Users can have multiple credentials for different devices.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ShotElixir.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webauthn_credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :sign_count, :integer, default: 0
    field :transports, {:array, :string}, default: []
    field :backed_up, :boolean, default: false
    field :backup_eligible, :boolean, default: false
    field :attestation_type, :string
    field :name, :string
    field :last_used_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new WebAuthn credential.
  """
  def create_changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :user_id,
      :credential_id,
      :public_key,
      :sign_count,
      :transports,
      :backed_up,
      :backup_eligible,
      :attestation_type,
      :name
    ])
    |> validate_required([:user_id, :credential_id, :public_key, :name])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:credential_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating credential after successful authentication.
  Updates sign_count and last_used_at timestamp.
  """
  def authentication_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:sign_count, :last_used_at])
    |> validate_required([:sign_count])
  end

  @doc """
  Changeset for renaming a credential.
  """
  def rename_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
