defmodule ShotElixir.Services.WebAuthnServiceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Services.WebAuthnService
  alias ShotElixir.Accounts
  alias ShotElixir.Accounts.{WebauthnCredential, WebauthnChallenge}

  @valid_user_attrs %{
    email: "webauthn-test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  }

  describe "generate_registration_options/1" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      %{user: user}
    end

    test "returns registration options for a user", %{user: user} do
      {:ok, options} = WebAuthnService.generate_registration_options(user)

      assert options.challenge
      assert options.rp.name == "Chi War"
      assert options.rp.id
      assert options.user.id
      assert options.user.name == user.email
      # displayName uses user.name (first + last) when available, falls back to email
      assert options.user.displayName == user.name
      assert options.pubKeyCredParams
      assert options.timeout == 120_000
      assert options.attestation == "none"
      assert options.excludeCredentials == []
      assert options.authenticatorSelection
      assert options.challenge_id
    end

    test "stores challenge in database", %{user: user} do
      {:ok, options} = WebAuthnService.generate_registration_options(user)

      challenge = Repo.get(WebauthnChallenge, options.challenge_id)
      assert challenge
      assert challenge.user_id == user.id
      assert challenge.challenge_type == "registration"
      assert challenge.used == false
      assert challenge.expires_at
    end

    test "excludes existing credentials", %{user: user} do
      # Create an existing credential
      credential_id = :crypto.strong_rand_bytes(32)
      public_key = :crypto.strong_rand_bytes(64)

      {:ok, _credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: credential_id,
          public_key: public_key,
          name: "Existing Passkey",
          transports: ["internal"]
        })
        |> Repo.insert()

      {:ok, options} = WebAuthnService.generate_registration_options(user)

      assert length(options.excludeCredentials) == 1
      exclude = hd(options.excludeCredentials)
      assert exclude.type == "public-key"
      assert exclude.transports == ["internal"]
    end
  end

  describe "generate_authentication_options/1" do
    test "returns options with allowCredentials for user with passkeys" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      # Create a credential for this user
      credential_id = :crypto.strong_rand_bytes(32)
      public_key = :crypto.strong_rand_bytes(64)

      {:ok, _credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: credential_id,
          public_key: public_key,
          name: "Test Passkey",
          transports: ["internal", "hybrid"]
        })
        |> Repo.insert()

      {:ok, options} = WebAuthnService.generate_authentication_options(user.email)

      assert options.challenge
      assert options.timeout == 120_000
      assert options.rpId
      assert options.userVerification == "preferred"
      assert options.challenge_id
      assert length(options.allowCredentials) == 1

      cred = hd(options.allowCredentials)
      assert cred.type == "public-key"
      assert cred.transports == ["internal", "hybrid"]
    end

    test "returns fake options for non-existent user (prevents enumeration)" do
      {:ok, options} = WebAuthnService.generate_authentication_options("nonexistent@example.com")

      assert options.challenge
      assert options.timeout == 120_000
      assert options.rpId
      assert options.allowCredentials == []
      assert options.challenge_id == nil
    end

    test "returns fake options for user without passkeys (prevents enumeration)" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      {:ok, options} = WebAuthnService.generate_authentication_options(user.email)

      # Should return the same structure as non-existent user
      assert options.challenge
      assert options.timeout == 120_000
      assert options.rpId
      assert options.allowCredentials == []
      assert options.challenge_id == nil
    end
  end

  describe "generate_authentication_options_for_user/1" do
    test "returns fake options when user has no passkeys" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      {:ok, options} = WebAuthnService.generate_authentication_options_for_user(user)

      assert options.challenge
      assert options.allowCredentials == []
      assert options.challenge_id == nil
    end

    test "returns real options when user has passkeys" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      # Create a credential
      {:ok, _credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Test Passkey"
        })
        |> Repo.insert()

      {:ok, options} = WebAuthnService.generate_authentication_options_for_user(user)

      assert options.challenge
      assert length(options.allowCredentials) == 1
      assert options.challenge_id != nil
    end
  end

  describe "list_credentials/1" do
    test "returns empty list for user with no credentials" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      credentials = WebAuthnService.list_credentials(user)
      assert credentials == []
    end

    test "returns credentials ordered by inserted_at desc" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      # Create first credential
      {:ok, cred1} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "First Passkey"
        })
        |> Repo.insert()

      # Create second credential
      {:ok, cred2} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Second Passkey"
        })
        |> Repo.insert()

      # Manually adjust timestamps to ensure ordering
      # (utc_datetime only has second precision, so we use explicit timestamps)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -3600, :second)

      Repo.update_all(
        from(c in WebauthnCredential, where: c.id == ^cred1.id),
        set: [inserted_at: past]
      )

      Repo.update_all(
        from(c in WebauthnCredential, where: c.id == ^cred2.id),
        set: [inserted_at: now]
      )

      credentials = WebAuthnService.list_credentials(user)

      assert length(credentials) == 2
      # Most recent first
      assert hd(credentials).id == cred2.id
      assert List.last(credentials).id == cred1.id
    end
  end

  describe "delete_credential/2" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Test Passkey"
        })
        |> Repo.insert()

      %{user: user, credential: credential}
    end

    test "deletes user's own credential", %{user: user, credential: credential} do
      assert {:ok, _deleted} = WebAuthnService.delete_credential(user, credential.id)

      assert Repo.get(WebauthnCredential, credential.id) == nil
    end

    test "returns error when credential not found", %{user: user} do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = WebAuthnService.delete_credential(user, fake_id)
    end

    test "cannot delete another user's credential", %{credential: credential} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      assert {:error, :not_found} = WebAuthnService.delete_credential(other_user, credential.id)

      # Credential should still exist
      assert Repo.get(WebauthnCredential, credential.id) != nil
    end
  end

  describe "rename_credential/3" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      {:ok, credential} =
        %WebauthnCredential{}
        |> WebauthnCredential.create_changeset(%{
          user_id: user.id,
          credential_id: :crypto.strong_rand_bytes(32),
          public_key: :crypto.strong_rand_bytes(64),
          name: "Original Name"
        })
        |> Repo.insert()

      %{user: user, credential: credential}
    end

    test "renames user's own credential", %{user: user, credential: credential} do
      {:ok, updated} = WebAuthnService.rename_credential(user, credential.id, "New Name")

      assert updated.name == "New Name"
      assert updated.id == credential.id
    end

    test "returns error when credential not found", %{user: user} do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = WebAuthnService.rename_credential(user, fake_id, "New Name")
    end

    test "cannot rename another user's credential", %{credential: credential} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other2@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      assert {:error, :not_found} =
               WebAuthnService.rename_credential(other_user, credential.id, "Hacked Name")

      # Name should not have changed
      original = Repo.get(WebauthnCredential, credential.id)
      assert original.name == "Original Name"
    end
  end
end
