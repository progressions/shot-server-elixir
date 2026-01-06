defmodule ShotElixir.AI.Providers.GrokProviderTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.AI.Providers.GrokProvider
  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential
  alias ShotElixir.Accounts

  defp create_user do
    {:ok, user} =
      Accounts.create_user(%{
        "email" => "grok-test-#{System.unique_integer()}@example.com",
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

    test "returns {:ok, credential} for valid grok credential with API key", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-valid-api-key"
        })

      assert {:ok, ^credential} = GrokProvider.validate_credential(credential)
    end

    test "returns {:error, :invalid} for non-grok provider", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "openai",
          "api_key" => "sk-valid-api-key"
        })

      assert {:error, :invalid} = GrokProvider.validate_credential(credential)
    end

    test "returns {:error, :invalid} for credential without API key", %{user: user} do
      # Create a credential struct directly in DB without API key to test validation
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        provider: "grok",
        api_key_encrypted: nil
      }

      assert {:error, :invalid} = GrokProvider.validate_credential(credential)
    end
  end

  describe "send_chat_request/3" do
    test "returns error for invalid credential" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "grok",
        api_key_encrypted: nil
      }

      assert {:error, :invalid_credential} = GrokProvider.send_chat_request(credential, "test")
    end
  end

  describe "generate_images/4" do
    test "returns error for invalid credential" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "grok",
        api_key_encrypted: nil
      }

      assert {:error, :invalid_credential} = GrokProvider.generate_images(credential, "test", 1)
    end
  end
end
