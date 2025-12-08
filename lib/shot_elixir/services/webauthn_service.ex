defmodule ShotElixir.Services.WebAuthnService do
  @moduledoc """
  Service for handling WebAuthn/passkey registration and authentication.

  Uses the wax library for FIDO2/WebAuthn operations.
  """

  alias ShotElixir.Repo
  alias ShotElixir.Accounts
  alias ShotElixir.Accounts.{User, WebauthnCredential, WebauthnChallenge}
  import Ecto.Query

  # Configuration
  @rp_name "Chi War"

  @doc """
  Generates a new registration challenge for a user to register a passkey.

  Returns options to be sent to the browser's WebAuthn API.
  """
  def generate_registration_options(%User{} = user) do
    # Get existing credentials to exclude
    existing_credentials = get_user_credentials(user.id)

    exclude_credentials =
      Enum.map(existing_credentials, fn cred ->
        %{
          id: Base.url_encode64(cred.credential_id, padding: false),
          type: "public-key",
          transports: cred.transports || []
        }
      end)

    # Generate challenge using wax
    challenge = Wax.new_registration_challenge(wax_options())

    # Store challenge in database
    {:ok, stored_challenge} = store_challenge(user.id, challenge.bytes, "registration")

    # Return WebAuthn options for the browser
    {:ok,
     %{
       challenge: Base.url_encode64(challenge.bytes, padding: false),
       rp: %{
         name: @rp_name,
         id: rp_id()
       },
       user: %{
         id: Base.url_encode64(user.id, padding: false),
         name: user.email,
         displayName: user.name || user.email
       },
       pubKeyCredParams: [
         %{alg: -7, type: "public-key"},
         # ES256
         %{alg: -257, type: "public-key"}
         # RS256
       ],
       timeout: 120_000,
       attestation: "none",
       excludeCredentials: exclude_credentials,
       # authenticatorAttachment: "platform" restricts to built-in authenticators
       # (Touch ID, Face ID, Windows Hello). This is intentional for Chi War to
       # provide a simpler user experience. Remove this line to allow security keys.
       authenticatorSelection: %{
         authenticatorAttachment: "platform",
         requireResidentKey: false,
         residentKey: "preferred",
         userVerification: "preferred"
       },
       challenge_id: stored_challenge.id
     }}
  end

  @doc """
  Verifies a registration response and stores the credential.

  Parameters:
    - user: The user registering the passkey
    - attestation_object: Base64url encoded attestation object from browser
    - client_data_json: Base64url encoded client data JSON from browser
    - challenge_id: ID of the stored challenge
    - name: User-provided name for the passkey
    - transports: Optional list of transport types (e.g., ["internal", "hybrid"])
  """
  def verify_registration(
        %User{} = user,
        attestation_object_b64,
        client_data_json_b64,
        challenge_id,
        name,
        transports \\ []
      ) do
    with {:ok, challenge} <- get_and_validate_challenge(challenge_id, "registration", user.id),
         {:ok, attestation_object} <- decode_base64url(attestation_object_b64),
         {:ok, client_data_json} <- decode_base64url(client_data_json_b64),
         wax_challenge <- build_wax_challenge(challenge.challenge, :attestation),
         {:ok, {authenticator_data, _attestation_result}} <-
           Wax.register(attestation_object, client_data_json, wax_challenge) do
      # Extract credential data
      attested_data = authenticator_data.attested_credential_data

      # Mark challenge as used
      mark_challenge_used(challenge)

      # Store the credential with transport information
      create_credential(user, %{
        credential_id: attested_data.credential_id,
        public_key: :erlang.term_to_binary(attested_data.credential_public_key),
        sign_count: authenticator_data.sign_count,
        transports: transports,
        name: name,
        backed_up: authenticator_data.flag_credential_backed_up,
        backup_eligible: authenticator_data.flag_backup_eligible
      })
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates authentication options for a user to authenticate with a passkey.

  Parameters:
    - email: The user's email address (to look up their credentials)
  """
  def generate_authentication_options(email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        # Return generic options to prevent user enumeration
        generate_empty_authentication_options()

      user ->
        generate_authentication_options_for_user(user)
    end
  end

  @doc """
  Generates authentication options for a specific user.

  Returns fake options if the user has no passkeys to prevent user enumeration.
  """
  def generate_authentication_options_for_user(%User{} = user) do
    credentials = get_user_credentials(user.id)

    if Enum.empty?(credentials) do
      # Return fake options to prevent user enumeration
      # (user exists but has no passkeys should look same as user doesn't exist)
      generate_empty_authentication_options()
    else
      allow_credentials =
        Enum.map(credentials, fn cred ->
          %{
            id: Base.url_encode64(cred.credential_id, padding: false),
            type: "public-key",
            transports: cred.transports || []
          }
        end)

      # Generate challenge
      challenge = Wax.new_authentication_challenge(wax_options())

      # Store challenge
      {:ok, stored_challenge} = store_challenge(user.id, challenge.bytes, "authentication")

      {:ok,
       %{
         challenge: Base.url_encode64(challenge.bytes, padding: false),
         timeout: 120_000,
         rpId: rp_id(),
         allowCredentials: allow_credentials,
         userVerification: "preferred",
         challenge_id: stored_challenge.id
       }}
    end
  end

  @doc """
  Verifies an authentication response.

  Returns {:ok, user} on success, {:error, reason} on failure.
  """
  def verify_authentication(
        credential_id_b64,
        authenticator_data_b64,
        signature_b64,
        client_data_json_b64,
        challenge_id
      ) do
    with {:ok, credential_id} <- decode_base64url(credential_id_b64),
         {:ok, credential} <- get_credential_by_id(credential_id),
         {:ok, challenge} <-
           get_and_validate_challenge(challenge_id, "authentication", credential.user_id),
         {:ok, authenticator_data} <- decode_base64url(authenticator_data_b64),
         {:ok, signature} <- decode_base64url(signature_b64),
         {:ok, client_data_json} <- decode_base64url(client_data_json_b64),
         _public_key <- :erlang.binary_to_term(credential.public_key),
         wax_challenge <- build_wax_challenge_with_credentials(challenge.challenge, credential),
         {:ok, updated_auth_data} <-
           Wax.authenticate(
             credential_id,
             authenticator_data,
             signature,
             client_data_json,
             wax_challenge
           ) do
      # Mark challenge as used
      mark_challenge_used(challenge)

      # Update sign count and last used
      update_credential_after_auth(credential, updated_auth_data.sign_count)

      # Return the user
      {:ok, Repo.preload(credential, :user).user}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all passkey credentials for a user.
  """
  def list_credentials(%User{} = user) do
    get_user_credentials(user.id)
  end

  @doc """
  Deletes a passkey credential.
  """
  def delete_credential(%User{} = user, credential_id) do
    case Repo.get_by(WebauthnCredential, id: credential_id, user_id: user.id) do
      nil -> {:error, :not_found}
      credential -> Repo.delete(credential)
    end
  end

  @doc """
  Renames a passkey credential.
  """
  def rename_credential(%User{} = user, credential_id, new_name) do
    case Repo.get_by(WebauthnCredential, id: credential_id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      credential ->
        credential
        |> WebauthnCredential.rename_changeset(%{name: new_name})
        |> Repo.update()
    end
  end

  # Private functions

  defp get_user_credentials(user_id) do
    WebauthnCredential
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  defp store_challenge(user_id, challenge_bytes, challenge_type) do
    %WebauthnChallenge{}
    |> WebauthnChallenge.create_changeset(%{
      user_id: user_id,
      challenge: challenge_bytes,
      challenge_type: challenge_type
    })
    |> Repo.insert()
  end

  defp get_and_validate_challenge(challenge_id, expected_type, expected_user_id) do
    case Repo.get(WebauthnChallenge, challenge_id) do
      nil ->
        {:error, :challenge_not_found}

      challenge ->
        cond do
          challenge.used ->
            {:error, :challenge_already_used}

          challenge.challenge_type != expected_type ->
            {:error, :invalid_challenge_type}

          challenge.user_id != expected_user_id ->
            {:error, :challenge_user_mismatch}

          not WebauthnChallenge.valid?(challenge) ->
            {:error, :challenge_expired}

          true ->
            {:ok, challenge}
        end
    end
  end

  defp mark_challenge_used(challenge) do
    challenge
    |> WebauthnChallenge.mark_used_changeset()
    |> Repo.update()
  end

  defp create_credential(%User{} = user, attrs) do
    %WebauthnCredential{}
    |> WebauthnCredential.create_changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  defp get_credential_by_id(credential_id) do
    case Repo.get_by(WebauthnCredential, credential_id: credential_id) do
      nil -> {:error, :credential_not_found}
      credential -> {:ok, credential}
    end
  end

  defp update_credential_after_auth(credential, new_sign_count) do
    credential
    |> WebauthnCredential.authentication_changeset(%{
      sign_count: new_sign_count,
      last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  defp generate_empty_authentication_options do
    # Generate fake challenge to prevent user enumeration timing attacks
    challenge = Wax.new_authentication_challenge(wax_options())

    {:ok,
     %{
       challenge: Base.url_encode64(challenge.bytes, padding: false),
       timeout: 120_000,
       rpId: rp_id(),
       allowCredentials: [],
       userVerification: "preferred",
       challenge_id: nil
     }}
  end

  defp build_wax_challenge(challenge_bytes, type) do
    %Wax.Challenge{
      bytes: challenge_bytes,
      origin: origin(),
      rp_id: rp_id(),
      user_verification: "preferred",
      type: type,
      issued_at: System.system_time(:second),
      origin_verify_fun: {Wax, :origins_match?, []}
    }
  end

  defp build_wax_challenge_with_credentials(challenge_bytes, credential) do
    public_key = :erlang.binary_to_term(credential.public_key)

    %Wax.Challenge{
      bytes: challenge_bytes,
      origin: origin(),
      rp_id: rp_id(),
      user_verification: "preferred",
      type: :authentication,
      issued_at: System.system_time(:second),
      origin_verify_fun: {Wax, :origins_match?, []},
      allow_credentials: [{credential.credential_id, public_key}]
    }
  end

  defp wax_options do
    [
      origin: origin(),
      rp_id: rp_id()
    ]
  end

  defp origin do
    Application.get_env(:shot_elixir, :webauthn_origin, "https://chiwar.net")
  end

  defp rp_id do
    Application.get_env(:shot_elixir, :webauthn_rp_id, "chiwar.net")
  end

  defp decode_base64url(data) when is_binary(data) do
    case Base.url_decode64(data, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64url}
    end
  end

  defp decode_base64url(_), do: {:error, :invalid_base64url}
end
