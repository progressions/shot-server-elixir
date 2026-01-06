defmodule ShotElixir.AI.ProviderTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.AI.Provider
  alias ShotElixir.AI.Providers.{GrokProvider, OpenAIProvider, GeminiProvider}
  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential
  alias ShotElixir.Accounts

  defp create_user do
    {:ok, user} =
      Accounts.create_user(%{
        "email" => "provider-test-#{System.unique_integer()}@example.com",
        "password" => "password123",
        "first_name" => "Test",
        "last_name" => "User"
      })

    user
  end

  describe "get_provider/1" do
    test "returns GrokProvider for grok provider" do
      assert {:ok, GrokProvider} = Provider.get_provider("grok")
    end

    test "returns OpenAIProvider for openai provider" do
      assert {:ok, OpenAIProvider} = Provider.get_provider("openai")
    end

    test "returns GeminiProvider for gemini provider" do
      assert {:ok, GeminiProvider} = Provider.get_provider("gemini")
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = Provider.get_provider("unknown")
    end

    test "returns error for nil provider" do
      assert {:error, :unknown_provider} = Provider.get_provider(nil)
    end
  end

  describe "send_chat_request/3" do
    setup do
      {:ok, user: create_user()}
    end

    test "returns error for credential with unknown provider", %{user: user} do
      # Create a credential struct directly with invalid provider
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        provider: "invalid_provider"
      }

      assert {:error, :unknown_provider} = Provider.send_chat_request(credential, "test")
    end
  end

  describe "validate_credential/1" do
    setup do
      {:ok, user: create_user()}
    end

    test "validates grok credential", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-valid-key"
        })

      assert {:ok, ^credential} = Provider.validate_credential(credential)
    end

    test "validates openai credential", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "openai",
          "api_key" => "sk-valid-key"
        })

      assert {:ok, ^credential} = Provider.validate_credential(credential)
    end

    test "validates gemini credential with valid tokens", %{user: user} do
      future_expiry = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "gemini",
          "access_token" => "ya29.valid-token",
          "refresh_token" => "1//valid-refresh",
          "token_expires_at" => future_expiry
        })

      assert {:ok, ^credential} = Provider.validate_credential(credential)
    end

    test "returns error for unknown provider" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "unknown"
      }

      assert {:error, :unknown_provider} = Provider.validate_credential(credential)
    end
  end
end
