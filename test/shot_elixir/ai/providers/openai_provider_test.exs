defmodule ShotElixir.AI.Providers.OpenAIProviderTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.AI.Providers.OpenAIProvider
  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential
  alias ShotElixir.Accounts

  defp create_user do
    {:ok, user} =
      Accounts.create_user(%{
        "email" => "openai-test-#{System.unique_integer()}@example.com",
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

    test "returns {:ok, credential} for valid openai credential with API key", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "openai",
          "api_key" => "sk-valid-api-key"
        })

      assert {:ok, ^credential} = OpenAIProvider.validate_credential(credential)
    end

    test "returns {:error, :invalid} for non-openai provider", %{user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-valid-api-key"
        })

      assert {:error, :invalid} = OpenAIProvider.validate_credential(credential)
    end

    test "returns {:error, :invalid} for credential without API key", %{user: user} do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: user.id,
        provider: "openai",
        api_key_encrypted: nil
      }

      assert {:error, :invalid} = OpenAIProvider.validate_credential(credential)
    end
  end

  describe "send_chat_request/3" do
    test "returns error for invalid credential" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "openai",
        api_key_encrypted: nil
      }

      assert {:error, :invalid_credential} = OpenAIProvider.send_chat_request(credential, "test")
    end
  end

  describe "generate_images/4" do
    test "returns error for invalid credential" do
      credential = %AiCredential{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        provider: "openai",
        api_key_encrypted: nil
      }

      assert {:error, :invalid_credential} = OpenAIProvider.generate_images(credential, "test", 1)
    end
  end
end
