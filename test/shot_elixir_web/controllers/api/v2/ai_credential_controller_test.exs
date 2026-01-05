defmodule ShotElixirWeb.Api.V2.AiCredentialControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.AiCredentials
  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create a user
    {:ok, user} =
      Accounts.create_user(%{
        "email" => "ai_cred_test_#{System.unique_integer()}@example.com",
        "password" => "password123",
        "first_name" => "Test",
        "last_name" => "User"
      })

    {:ok, conn: put_req_header(conn, "accept", "application/json"), user: user}
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all credentials for current user", %{conn: conn, user: user} do
      # Create some credentials
      {:ok, _grok} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-test-key-12345678"
        })

      {:ok, _openai} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "openai",
          "api_key" => "sk-test-key-abcdefgh"
        })

      conn =
        conn
        |> authenticate(user)
        |> get(~p"/api/v2/ai_credentials")

      response = json_response(conn, 200)
      assert length(response["ai_credentials"]) == 2

      providers = Enum.map(response["ai_credentials"], & &1["provider"])
      assert "grok" in providers
      assert "openai" in providers

      # Verify keys are masked
      grok_cred = Enum.find(response["ai_credentials"], &(&1["provider"] == "grok"))
      assert grok_cred["api_key_hint"] == "...12345678"
      assert grok_cred["connected"] == true
    end

    test "returns empty list when user has no credentials", %{conn: conn, user: user} do
      conn =
        conn
        |> authenticate(user)
        |> get(~p"/api/v2/ai_credentials")

      response = json_response(conn, 200)
      assert response["ai_credentials"] == []
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/ai_credentials")
      assert json_response(conn, 401)
    end
  end

  describe "create" do
    test "creates credential with valid API key", %{conn: conn, user: user} do
      conn =
        conn
        |> authenticate(user)
        |> post(~p"/api/v2/ai_credentials", %{
          "ai_credential" => %{
            "provider" => "grok",
            "api_key" => "xai-new-api-key-12345"
          }
        })

      response = json_response(conn, 201)
      assert response["provider"] == "grok"
      assert response["connected"] == true
      assert response["api_key_hint"] == "...ey-12345"
      assert response["id"] != nil
    end

    test "creates credential with OAuth tokens for gemini", %{conn: conn, user: user} do
      expires_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

      conn =
        conn
        |> authenticate(user)
        |> post(~p"/api/v2/ai_credentials", %{
          "ai_credential" => %{
            "provider" => "gemini",
            "access_token" => "ya29.access-token",
            "refresh_token" => "1//refresh-token",
            "token_expires_at" => expires_at
          }
        })

      response = json_response(conn, 201)
      assert response["provider"] == "gemini"
      assert response["connected"] == true
      assert response["token_expires_at"] != nil
    end

    test "returns error for invalid provider", %{conn: conn, user: user} do
      conn =
        conn
        |> authenticate(user)
        |> post(~p"/api/v2/ai_credentials", %{
          "ai_credential" => %{
            "provider" => "invalid_provider",
            "api_key" => "some-key"
          }
        })

      response = json_response(conn, 422)
      assert response["errors"]["provider"] != nil
    end

    test "returns error for duplicate provider", %{conn: conn, user: user} do
      # Create first credential
      {:ok, _cred} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-first-key"
        })

      # Try to create duplicate
      conn =
        conn
        |> authenticate(user)
        |> post(~p"/api/v2/ai_credentials", %{
          "ai_credential" => %{
            "provider" => "grok",
            "api_key" => "xai-second-key"
          }
        })

      response = json_response(conn, 422)
      assert response["errors"] != nil
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/ai_credentials", %{
          "ai_credential" => %{
            "provider" => "grok",
            "api_key" => "xai-key"
          }
        })

      assert json_response(conn, 401)
    end
  end

  describe "update" do
    test "updates API key for existing credential", %{conn: conn, user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-old-key-12345"
        })

      conn =
        conn
        |> authenticate(user)
        |> put(~p"/api/v2/ai_credentials/#{credential.id}", %{
          "ai_credential" => %{
            "api_key" => "xai-new-key-67890"
          }
        })

      response = json_response(conn, 200)
      assert response["api_key_hint"] == "...ey-67890"
    end

    test "returns 404 for non-existent credential", %{conn: conn, user: user} do
      conn =
        conn
        |> authenticate(user)
        |> put(~p"/api/v2/ai_credentials/#{Ecto.UUID.generate()}", %{
          "ai_credential" => %{
            "api_key" => "xai-new-key"
          }
        })

      assert json_response(conn, 404)
    end

    test "returns 404 when trying to update another user's credential", %{conn: conn, user: user} do
      # Create another user with a credential
      {:ok, other_user} =
        Accounts.create_user(%{
          "email" => "other_#{System.unique_integer()}@example.com",
          "password" => "password123",
          "first_name" => "Other",
          "last_name" => "User"
        })

      {:ok, other_credential} =
        AiCredentials.create_credential(%{
          "user_id" => other_user.id,
          "provider" => "grok",
          "api_key" => "xai-other-key"
        })

      conn =
        conn
        |> authenticate(user)
        |> put(~p"/api/v2/ai_credentials/#{other_credential.id}", %{
          "ai_credential" => %{
            "api_key" => "xai-hacked-key"
          }
        })

      assert json_response(conn, 404)
    end
  end

  describe "delete" do
    test "deletes credential", %{conn: conn, user: user} do
      {:ok, credential} =
        AiCredentials.create_credential(%{
          "user_id" => user.id,
          "provider" => "grok",
          "api_key" => "xai-to-delete"
        })

      conn =
        conn
        |> authenticate(user)
        |> delete(~p"/api/v2/ai_credentials/#{credential.id}")

      assert response(conn, 204)

      # Verify it's deleted
      assert AiCredentials.get_credential(credential.id) == nil
    end

    test "returns 404 for non-existent credential", %{conn: conn, user: user} do
      conn =
        conn
        |> authenticate(user)
        |> delete(~p"/api/v2/ai_credentials/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end

    test "returns 404 when trying to delete another user's credential", %{conn: conn, user: user} do
      # Create another user with a credential
      {:ok, other_user} =
        Accounts.create_user(%{
          "email" => "other_del_#{System.unique_integer()}@example.com",
          "password" => "password123",
          "first_name" => "Other",
          "last_name" => "User"
        })

      {:ok, other_credential} =
        AiCredentials.create_credential(%{
          "user_id" => other_user.id,
          "provider" => "openai",
          "api_key" => "sk-other-key"
        })

      conn =
        conn
        |> authenticate(user)
        |> delete(~p"/api/v2/ai_credentials/#{other_credential.id}")

      assert json_response(conn, 404)

      # Verify it's NOT deleted
      assert AiCredentials.get_credential(other_credential.id) != nil
    end
  end
end
