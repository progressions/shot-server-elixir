defmodule ShotElixir.AiCredentials.AiCredential do
  @moduledoc """
  Schema for storing encrypted AI provider credentials.

  Supports:
  - API keys for Grok and OpenAI (stored encrypted)
  - OAuth tokens for Gemini (access_token, refresh_token, expiration)

  ## Changesets

  This schema uses two separate changesets:

  - `changeset/2` - For creating and updating credentials (provider, api_key, tokens).
    Does NOT include status fields. New credentials default to status "active".

  - `status_changeset/2` - For updating credential status (status, status_message).
    Use this after creation to mark a credential as "suspended" or "invalid".

  This separation ensures credential data updates and status updates are handled
  independently, preventing accidental status changes during normal edits.
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
    |> validate_credentials_provided()
    |> encrypt_api_key()
    |> encrypt_access_token()
    |> encrypt_refresh_token()
  end

  # Validate that appropriate credentials are provided for the provider type
  defp validate_credentials_provided(changeset) do
    provider = get_field(changeset, :provider)
    api_key = get_field(changeset, :api_key)
    access_token = get_field(changeset, :access_token)
    refresh_token = get_field(changeset, :refresh_token)

    case provider do
      provider when provider in ["grok", "openai"] ->
        if is_nil(api_key) or api_key == "" do
          add_error(changeset, :api_key, "is required for #{provider}")
        else
          changeset
        end

      "gemini" ->
        cond do
          is_nil(access_token) or access_token == "" ->
            add_error(changeset, :access_token, "is required for gemini")

          is_nil(refresh_token) or refresh_token == "" ->
            add_error(changeset, :refresh_token, "is required for gemini")

          true ->
            changeset
        end

      _ ->
        changeset
    end
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
