defmodule ShotElixir.AiCredentials do
  @moduledoc """
  Context module for managing AI provider credentials.

  Provides CRUD operations for AI credentials with automatic encryption
  of API keys and OAuth tokens.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.AiCredentials.AiCredential

  @doc """
  Creates a new AI credential.

  ## Parameters
    - attrs: Map containing :user_id, :provider, and either :api_key (for Grok/OpenAI)
      or :access_token/:refresh_token/:token_expires_at (for Gemini)

  ## Examples

      iex> create_credential(%{"user_id" => user_id, "provider" => "grok", "api_key" => "xai-key"})
      {:ok, %AiCredential{}}

      iex> create_credential(%{"user_id" => user_id, "provider" => "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def create_credential(attrs \\ %{}) do
    %AiCredential{}
    |> AiCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a credential by ID.

  Returns nil if not found.
  """
  def get_credential(id) do
    Repo.get(AiCredential, id)
  end

  @doc """
  Gets a credential by ID, raises if not found.
  """
  def get_credential!(id) do
    Repo.get!(AiCredential, id)
  end

  @doc """
  Gets a credential by user ID and provider.

  Returns nil if not found.

  ## Examples

      iex> get_credential_by_user_and_provider(user_id, "grok")
      %AiCredential{}

      iex> get_credential_by_user_and_provider(user_id, "openai")
      nil
  """
  def get_credential_by_user_and_provider(user_id, provider) do
    Repo.get_by(AiCredential, user_id: user_id, provider: provider)
  end

  @doc """
  Lists all credentials for a user.

  ## Examples

      iex> list_credentials_for_user(user_id)
      [%AiCredential{provider: "grok"}, %AiCredential{provider: "openai"}]
  """
  def list_credentials_for_user(user_id) do
    AiCredential
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.provider)
    |> Repo.all()
  end

  @doc """
  Updates an existing credential.

  ## Examples

      iex> update_credential(credential, %{"api_key" => "new-key"})
      {:ok, %AiCredential{}}
  """
  def update_credential(%AiCredential{} = credential, attrs) do
    credential
    |> AiCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a credential.

  ## Examples

      iex> delete_credential(credential)
      {:ok, %AiCredential{}}
  """
  def delete_credential(%AiCredential{} = credential) do
    Repo.delete(credential)
  end

  @doc """
  Gets the decrypted API key from a credential.

  The api_key_encrypted field is automatically decrypted by the Ecto type,
  so this just returns the value.

  ## Examples

      iex> get_decrypted_api_key(credential)
      {:ok, "xai-your-api-key"}
  """
  def get_decrypted_api_key(%AiCredential{api_key_encrypted: nil}), do: {:error, :no_key}
  def get_decrypted_api_key(%AiCredential{api_key_encrypted: key}), do: {:ok, key}

  @doc """
  Gets the decrypted access token from a credential.

  ## Examples

      iex> get_decrypted_access_token(credential)
      {:ok, "ya29.access-token"}
  """
  def get_decrypted_access_token(%AiCredential{access_token_encrypted: nil}),
    do: {:error, :no_token}

  def get_decrypted_access_token(%AiCredential{access_token_encrypted: token}), do: {:ok, token}

  @doc """
  Gets the decrypted refresh token from a credential.

  ## Examples

      iex> get_decrypted_refresh_token(credential)
      {:ok, "1//refresh-token"}
  """
  def get_decrypted_refresh_token(%AiCredential{refresh_token_encrypted: nil}),
    do: {:error, :no_token}

  def get_decrypted_refresh_token(%AiCredential{refresh_token_encrypted: token}), do: {:ok, token}

  @doc """
  Returns a masked version of the API key for display purposes.

  Shows only the last 8 characters prefixed with "..."

  ## Examples

      iex> mask_api_key(credential)
      "...abcd1234"
  """
  def mask_api_key(%AiCredential{api_key_encrypted: nil}), do: nil

  def mask_api_key(%AiCredential{api_key_encrypted: key}) when is_binary(key) do
    mask_key_string(key)
  end

  def mask_api_key(%AiCredential{} = credential) do
    case get_decrypted_api_key(credential) do
      {:ok, key} -> mask_key_string(key)
      _ -> nil
    end
  end

  defp mask_key_string(key) when is_binary(key) do
    if String.length(key) > 8 do
      "..." <> String.slice(key, -8..-1//1)
    else
      "********"
    end
  end

  @doc """
  Gets the credential for a campaign based on its ai_provider setting.

  Returns {:ok, credential} or {:error, :no_credential}

  ## Examples

      iex> get_credential_for_campaign(campaign)
      {:ok, %AiCredential{}}

      iex> get_credential_for_campaign(campaign_without_provider)
      {:error, :no_credential}
  """
  def get_credential_for_campaign(%{ai_provider: nil}), do: {:error, :no_credential}

  def get_credential_for_campaign(%{ai_provider: provider, user_id: user_id}) do
    case get_credential_by_user_and_provider(user_id, provider) do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  # Also support getting credential via gamemaster_id (some contexts use this)
  def get_credential_for_campaign(%{ai_provider: provider, gamemaster_id: gamemaster_id}) do
    case get_credential_by_user_and_provider(gamemaster_id, provider) do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  @doc """
  Checks if a user has a credential for the given provider.

  ## Examples

      iex> has_credential?(user_id, "grok")
      true
  """
  def has_credential?(user_id, provider) do
    AiCredential
    |> where([c], c.user_id == ^user_id and c.provider == ^provider)
    |> Repo.exists?()
  end

  @doc """
  Updates the status of a credential.

  ## Examples

      iex> update_status(credential, "suspended", "Billing hard limit reached")
      {:ok, %AiCredential{status: "suspended"}}
  """
  def update_status(%AiCredential{} = credential, status, message \\ nil) do
    credential
    |> AiCredential.status_changeset(%{status: status, status_message: message})
    |> Repo.update()
  end

  @doc """
  Marks a credential as suspended due to billing/quota issues.
  """
  def mark_suspended(%AiCredential{} = credential, message) do
    update_status(credential, "suspended", message)
  end

  @doc """
  Marks a credential as invalid due to authentication failure.
  """
  def mark_invalid(%AiCredential{} = credential, message \\ "Authentication failed") do
    update_status(credential, "invalid", message)
  end

  @doc """
  Reactivates a credential (e.g., after updating the API key).
  """
  def reactivate(%AiCredential{} = credential) do
    update_status(credential, "active", nil)
  end

  @doc """
  Checks if a credential is active and usable.
  """
  def active?(%AiCredential{status: "active"}), do: true
  def active?(_), do: false
end
