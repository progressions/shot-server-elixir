defmodule ShotElixirWeb.Api.V2.WebauthnControllerTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.Accounts
  alias ShotElixir.Accounts.WebauthnCredential
  alias ShotElixir.Guardian
  alias ShotElixir.Repo

  @valid_user_attrs %{
    email: "webauthn-controller-test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  }

  defp create_user_and_token(attrs \\ %{}) do
    user_attrs = Map.merge(@valid_user_attrs, attrs)
    {:ok, user} = Accounts.create_user(user_attrs)
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {user, token}
  end

  defp authenticated_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "POST /api/v2/webauthn/register/options" do
    test "returns registration options for authenticated user", %{conn: conn} do
      {user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/webauthn/register/options")

      response = json_response(conn, 200)

      assert response["challenge"]
      assert response["rp"]["name"] == "Chi War"
      assert response["rp"]["id"]
      assert response["user"]["name"] == user.email
      assert response["pubKeyCredParams"]
      assert response["timeout"] == 120_000
      assert response["challenge_id"]
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/webauthn/register/options")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "POST /api/v2/webauthn/register/verify" do
    setup %{conn: conn} do
      {user, token} = create_user_and_token()
      %{conn: conn, user: user, token: token}
    end

    test "returns error when required params are missing", %{conn: conn, token: token} do
      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/webauthn/register/verify", %{})

      response = json_response(conn, 400)
      assert response["error"] =~ "required"
    end

    test "returns error with invalid challenge_id", %{conn: conn, token: token} do
      conn =
        conn
        |> authenticated_conn(token)
        |> post(~p"/api/v2/webauthn/register/verify", %{
          "attestationObject" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false),
          "challengeId" => Ecto.UUID.generate(),
          "name" => "Test Passkey"
        })

      response = json_response(conn, 400)
      assert response["error"]
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/webauthn/register/verify", %{
          "attestationObject" => "fake",
          "clientDataJSON" => "fake",
          "challengeId" => "fake",
          "name" => "Test"
        })

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "POST /api/v2/webauthn/authenticate/options" do
    test "returns options for existing user with passkeys", %{conn: conn} do
      {user, _token} = create_user_and_token()

      # Create a credential for this user
      {:ok, _credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Test Passkey",
          transports: ["internal"]
        })
        |> Repo.insert()

      conn = post(conn, ~p"/api/v2/webauthn/authenticate/options", %{"email" => user.email})

      response = json_response(conn, 200)

      assert response["challenge"]
      assert response["rpId"]
      assert response["timeout"] == 120_000
      assert length(response["allowCredentials"]) == 1
      assert response["challenge_id"]
    end

    test "returns fake options for non-existent user (prevents enumeration)", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/webauthn/authenticate/options", %{
          "email" => "nonexistent@example.com"
        })

      response = json_response(conn, 200)

      # Should still return 200 with valid structure
      assert response["challenge"]
      assert response["rpId"]
      assert response["allowCredentials"] == []
      assert response["challenge_id"] == nil
    end

    test "returns fake options for user without passkeys (prevents enumeration)", %{conn: conn} do
      {user, _token} = create_user_and_token(%{email: "no-passkeys@example.com"})

      conn = post(conn, ~p"/api/v2/webauthn/authenticate/options", %{"email" => user.email})

      response = json_response(conn, 200)

      # Should return same structure as non-existent user
      assert response["challenge"]
      assert response["allowCredentials"] == []
      assert response["challenge_id"] == nil
    end

    test "returns error when email is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/webauthn/authenticate/options", %{})

      response = json_response(conn, 400)
      assert response["error"] == "Email is required"
    end
  end

  describe "POST /api/v2/webauthn/authenticate/verify" do
    test "returns error when required params are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/webauthn/authenticate/verify", %{})

      response = json_response(conn, 401)
      assert response["error"] =~ "required"
    end

    test "returns error with invalid challenge_id", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/webauthn/authenticate/verify", %{
          "credentialId" => Base.url_encode64("fake", padding: false),
          "authenticatorData" => Base.url_encode64("fake", padding: false),
          "signature" => Base.url_encode64("fake", padding: false),
          "clientDataJSON" => Base.url_encode64("fake", padding: false),
          "challengeId" => Ecto.UUID.generate()
        })

      response = json_response(conn, 401)
      assert response["error"]
    end
  end

  describe "GET /api/v2/webauthn/credentials" do
    test "returns empty list for user with no credentials", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> get(~p"/api/v2/webauthn/credentials")

      response = json_response(conn, 200)
      assert response["credentials"] == []
    end

    test "returns user's credentials", %{conn: conn} do
      {user, token} = create_user_and_token()

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "My MacBook",
          backed_up: true
        })
        |> Repo.insert()

      conn =
        conn
        |> authenticated_conn(token)
        |> get(~p"/api/v2/webauthn/credentials")

      response = json_response(conn, 200)
      assert length(response["credentials"]) == 1

      cred = hd(response["credentials"])
      assert cred["id"] == credential.id
      assert cred["name"] == "My MacBook"
      assert cred["backed_up"] == true
      assert cred["created_at"]
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/webauthn/credentials")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "DELETE /api/v2/webauthn/credentials/:id" do
    test "deletes user's own credential", %{conn: conn} do
      {user, token} = create_user_and_token()

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "To Delete"
        })
        |> Repo.insert()

      conn =
        conn
        |> authenticated_conn(token)
        |> delete(~p"/api/v2/webauthn/credentials/#{credential.id}")

      response = json_response(conn, 200)
      assert response["message"] =~ "deleted"

      assert Repo.get(WebauthnCredential, credential.id) == nil
    end

    test "returns 404 for non-existent credential", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> delete(~p"/api/v2/webauthn/credentials/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "cannot delete another user's credential", %{conn: conn} do
      {user1, _token1} = create_user_and_token(%{email: "user1@example.com"})
      {_user2, token2} = create_user_and_token(%{email: "user2@example.com"})

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user1.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "User1's Passkey"
        })
        |> Repo.insert()

      # User2 tries to delete User1's credential
      conn =
        conn
        |> authenticated_conn(token2)
        |> delete(~p"/api/v2/webauthn/credentials/#{credential.id}")

      assert json_response(conn, 404)["error"] =~ "not found"

      # Credential should still exist
      assert Repo.get(WebauthnCredential, credential.id) != nil
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/webauthn/credentials/#{Ecto.UUID.generate()}")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end

  describe "PATCH /api/v2/webauthn/credentials/:id" do
    test "renames user's own credential", %{conn: conn} do
      {user, token} = create_user_and_token()

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Old Name"
        })
        |> Repo.insert()

      conn =
        conn
        |> authenticated_conn(token)
        |> patch(~p"/api/v2/webauthn/credentials/#{credential.id}", %{"name" => "New Name"})

      response = json_response(conn, 200)
      assert response["id"] == credential.id
      assert response["name"] == "New Name"
    end

    test "returns error when name is missing", %{conn: conn} do
      {user, token} = create_user_and_token()

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Test"
        })
        |> Repo.insert()

      conn =
        conn
        |> authenticated_conn(token)
        |> patch(~p"/api/v2/webauthn/credentials/#{credential.id}", %{})

      assert json_response(conn, 400)["error"] == "Name is required"
    end

    test "returns 404 for non-existent credential", %{conn: conn} do
      {_user, token} = create_user_and_token()

      conn =
        conn
        |> authenticated_conn(token)
        |> patch(~p"/api/v2/webauthn/credentials/#{Ecto.UUID.generate()}", %{"name" => "New"})

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "cannot rename another user's credential", %{conn: conn} do
      {user1, _token1} = create_user_and_token(%{email: "rename1@example.com"})
      {_user2, token2} = create_user_and_token(%{email: "rename2@example.com"})

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user1.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Original"
        })
        |> Repo.insert()

      conn =
        conn
        |> authenticated_conn(token2)
        |> patch(~p"/api/v2/webauthn/credentials/#{credential.id}", %{"name" => "Hacked"})

      assert json_response(conn, 404)["error"] =~ "not found"

      # Name should not have changed
      assert Repo.get(WebauthnCredential, credential.id).name == "Original"
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn =
        patch(conn, ~p"/api/v2/webauthn/credentials/#{Ecto.UUID.generate()}", %{"name" => "Test"})

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end
  end
end
