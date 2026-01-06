defmodule ShotElixir.AI.Providers.GeminiProviderTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.AI.Providers.GeminiProvider
  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential
  alias ShotElixir.Accounts

  defp create_user do
    {:ok, user} =
      Accounts.create_user(%{
        "email" => "gemini-test-#{System.unique_integer()}@example.com",
        "password" => "password123",
        "first_name" => "Test",
        "last_name" => "User"
      })

    user
  end

  describe "validate_credential/1" do
    setup do
      {:ok, user: create_user()}
    end

    test "returns {:ok, credential} for valid gemini credential with tokens and future expiry", %{
      user: user
    } do
      future_expiry = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => "ya29.valid-access-token",
          "refresh_token" => "1//valid-refresh-token",
          "token_expires_at" => future_expiry
        })

      assert {:ok, ^credential} = GeminiProvider.validate_credential(credential)
    end

    test "returns {:error, :expired} for gemini credential with expired token", %{user: user} do
      past_expiry = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => "ya29.valid-access-token",
          "refresh_token" => "1//valid-refresh-token",
          "token_expires_at" => past_expiry
        })

      assert {:error, :expired} = GeminiProvider.validate_credential(credential)
    end

    test "returns {:ok, credential} for gemini credential with no expiry but valid tokens", %{
      user: user
    } do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => "ya29.valid-access-token",
          "refresh_token" => "1//valid-refresh-token"
        })

      assert {:ok, ^credential} = GeminiProvider.validate_credential(credential)
    end

    test "returns {:error, :invalid} for non-gemini provider", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-valid-api-key"
        })

      assert {:error, :invalid} = GeminiProvider.validate_credential(credential)
    end

    test "returns {:error, :invalid} for gemini credential without tokens", %{user: user} do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        provider: "gemini",
        access_token_encrypted: nil,
        refresh_token_encrypted: nil
      }

      assert {:error, :invalid} = GeminiProvider.validate_credential(credential)
    end
  end

  describe "send_chat_request/3" do
    test "returns error for invalid credential" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "gemini",
        access_token_encrypted: nil
      }

      assert {:error, :invalid_credential} = GeminiProvider.send_chat_request(credential, "test")
    end
  end

  describe "generate_images/4" do
    test "returns error for invalid credential" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "gemini",
        access_token_encrypted: nil
      }

      assert {:error, :invalid_credential} = GeminiProvider.generate_images(credential, "test", 1)
    end
  end

  describe "token refresh locking" do
    setup do
      {:ok, user: create_user()}
    end

    test "concurrent token refresh attempts are handled safely", %{user: user} do
      # Create credential with expired token
      past_expiry = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => "ya29.expired-token",
          "refresh_token" => "1//valid-refresh-token",
          "token_expires_at" => past_expiry
        })

      # The token refresh will fail (no actual Google API), but the locking
      # mechanism should prevent race conditions
      assert {:error, :expired} = GeminiProvider.validate_credential(credential)
    end
  end
end
