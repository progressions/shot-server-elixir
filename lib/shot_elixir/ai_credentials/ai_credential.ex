defmodule ShotElixir.AiCredentials.AiCredential do
  @moduledoc """
  Schema for storing encrypted AI provider credentials.

  Supports:
  - API keys for Grok and OpenAI (stored encrypted)
  - OAuth tokens for Gemini (access_token, refresh_token, expiration)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ShotElixir.Accounts.User
  alias ShotElixir.Encrypted.Binary, as: EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_providers ["grok", "openai", "gemini"]
  @valid_statuses ["active", "suspended", "invalid"]

  schema "ai_credentials" do
    belongs_to :user, User

    field :provider, :string
    field :api_key_encrypted, EncryptedBinary
    field :access_token_encrypted, EncryptedBinary
    field :refresh_token_encrypted, EncryptedBinary
    field :token_expires_at, :utc_datetime

    # Status tracking for integration health
    field :status, :string, default: "active"
    field :status_message, :string
    field :status_updated_at, :utc_datetime

    # Virtual fields for input (not stored directly)
    field :api_key, :string, virtual: true
    field :access_token, :string, virtual: true
    field :refresh_token, :string, virtual: true

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an AI credential.

  Accepts virtual fields (api_key, access_token, refresh_token) and
  automatically encrypts them into the _encrypted fields.
  """
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :user_id,
      :provider,
      :api_key,
      :access_token,
      :refresh_token,
      :token_expires_at
    ])
    |> validate_required([:user_id, :provider])
    |> validate_inclusion(:provider, @valid_providers)
    |> unique_constraint([:user_id, :provider],
      name: :ai_credentials_user_id_provider_index,
      message: "has already been taken"
    )
    |> encrypt_api_key()
    |> encrypt_access_token()
    |> encrypt_refresh_token()
  end

  @doc """
  Returns the list of valid provider names.
  """
  def valid_providers, do: @valid_providers

  @doc """
  Returns the list of valid status values.
  """
  def valid_statuses, do: @valid_statuses

  @doc """
  Creates a changeset for updating credential status.

  Used when marking a credential as suspended (billing issues) or invalid (auth failed).
  """
  def status_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:status, :status_message, :status_updated_at])
    |> validate_inclusion(:status, @valid_statuses)
    |> put_status_timestamp()
  end

  defp put_status_timestamp(changeset) do
    case get_change(changeset, :status) do
      nil ->
        changeset

      _ ->
        put_change(
          changeset,
          :status_updated_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )
    end
  end

  # Encrypt api_key virtual field into api_key_encrypted
  defp encrypt_api_key(changeset) do
    case get_change(changeset, :api_key) do
      nil -> changeset
      api_key -> put_change(changeset, :api_key_encrypted, api_key)
    end
  end

  # Encrypt access_token virtual field into access_token_encrypted
  defp encrypt_access_token(changeset) do
    case get_change(changeset, :access_token) do
      nil -> changeset
      token -> put_change(changeset, :access_token_encrypted, token)
    end
  end

  # Encrypt refresh_token virtual field into refresh_token_encrypted
  defp encrypt_refresh_token(changeset) do
    case get_change(changeset, :refresh_token) do
      nil -> changeset
      token -> put_change(changeset, :refresh_token_encrypted, token)
    end
  end
end
