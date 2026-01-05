defmodule ShotElixir.AiCredentialsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential
  alias ShotElixir.Accounts

  describe "ai_credentials" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "test-#{System.unique_integer()}@example.com",
          "password" => "password123",
          "first_name" => "Test",
          "last_name" => "User"
        })

      {:ok, user: user}
    end

    test "create_credential/1 creates a credential with valid attrs", %{user: user} do
      attrs = %{
        "user_id" => user.id,
        "provider" => "grok",
        "api_key" => "xai-test-api-key-12345"
      }

      assert {:ok, credential} = AiCredentials.create_credential(attrs)
      assert credential.user_id == user.id
      assert credential.provider == "grok"
      # API key is stored encrypted but auto-decrypted when loaded
      # The encrypted type handles encryption/decryption transparently
      assert credential.api_key_encrypted == "xai-test-api-key-12345"
      assert is_binary(credential.api_key_encrypted)
    end

    test "create_credential/1 with OAuth tokens for gemini", %{user: user} do
      attrs = %{
        "user_id" => user.id,
        "provider" => "gemini",
        "access_token" => "ya29.access-token-123",
        "refresh_token" => "1//refresh-token-456",
        "token_expires_at" => DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      assert {:ok, credential} = AiCredentials.create_credential(attrs)
      assert credential.provider == "gemini"
      assert credential.access_token_encrypted != nil
      assert credential.refresh_token_encrypted != nil
      assert credential.token_expires_at != nil
    end

    test "create_credential/1 fails with invalid provider", %{user: user} do
      attrs = %{
        "user_id" => user.id,
        "provider" => "invalid_provider",
        "api_key" => "some-key"
      }

      assert {:error, changeset} = AiCredentials.create_credential(attrs)
      assert "is invalid" in errors_on(changeset).provider
    end

    test "create_credential/1 enforces unique user_id + provider", %{user: user} do
      attrs = %{
        "user_id" => user.id,
        "provider" => "openai",
        "api_key" => "sk-first-key"
      }

      assert {:ok, _credential} = AiCredentials.create_credential(attrs)

      # Try to create another credential for same provider
      duplicate_attrs = %{
        "user_id" => user.id,
        "provider" => "openai",
        "api_key" => "sk-second-key"
      }

      assert {:error, changeset} = AiCredentials.create_credential(duplicate_attrs)
      # The unique constraint is on the composite [user_id, provider]
      # Error appears on first field in the constraint
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :user_id) or Map.has_key?(errors, :provider)
    end

    test "get_credential/1 returns the credential", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-key"
        })

      assert found = AiCredentials.get_credential(credential.id)
      assert found.id == credential.id
    end

    test "get_credential/1 returns nil for non-existent id" do
      assert AiCredentials.get_credential(Ecto.UUID.generate()) == nil
    end

    test "get_credential_by_user_and_provider/2 finds credential", %{user: user} do
      {:ok, _credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-key"
        })

      assert found = AiCredentials.get_credential_by_user_and_provider(user.id, "grok")
      assert found.provider == "grok"
    end

    test "get_credential_by_user_and_provider/2 returns nil when not found", %{user: user} do
      assert AiCredentials.get_credential_by_user_and_provider(user.id, "openai") == nil
    end

    test "list_credentials_for_user/1 returns all user credentials", %{user: user} do
      {:ok, _grok} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-key"
        })

      {:ok, _openai} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "openai",
          "api_key" => "sk-key"
        })

      credentials = AiCredentials.list_credentials_for_user(user.id)
      assert length(credentials) == 2
      providers = Enum.map(credentials, & &1.provider)
      assert "grok" in providers
      assert "openai" in providers
    end

    test "update_credential/2 updates the API key", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "old-key"
        })

      assert {:ok, updated} =
               AiCredentials.update_credential(credential, %{"api_key" => "new-key"})

      # Verify the encrypted value changed
      assert updated.api_key_encrypted != credential.api_key_encrypted
    end

    test "update_credential/2 updates OAuth tokens", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => "old-access-token",
          "refresh_token" => "old-refresh-token"
        })

      new_expires = DateTime.utc_now() |> DateTime.add(7200, :second)

      assert {:ok, updated} =
               AiCredentials.update_credential(credential, %{
                 "access_token" => "new-access-token",
                 "token_expires_at" => new_expires
               })

      assert updated.access_token_encrypted != credential.access_token_encrypted
      assert updated.token_expires_at == DateTime.truncate(new_expires, :second)
    end

    test "delete_credential/1 removes the credential", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-key"
        })

      assert {:ok, _deleted} = AiCredentials.delete_credential(credential)
      assert AiCredentials.get_credential(credential.id) == nil
    end

    test "get_decrypted_api_key/1 returns the original key", %{user: user} do
      original_key = "xai-my-secret-api-key-12345"

      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => original_key
        })

      assert AiCredentials.get_decrypted_api_key(credential) == {:ok, original_key}
    end

    test "get_decrypted_access_token/1 returns the original token", %{user: user} do
      original_token = "ya29.access-token-secret"

      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => original_token
        })

      assert AiCredentials.get_decrypted_access_token(credential) == {:ok, original_token}
    end

    test "mask_api_key/1 returns masked version", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-1234567890abcdef"
        })

      masked = AiCredentials.mask_api_key(credential)
      assert masked == "...90abcdef"
    end

    test "mask_api_key/1 returns nil for nil key" do
      assert AiCredentials.mask_api_key(%AiCredential{api_key_encrypted: nil}) == nil
    end
  end
end
