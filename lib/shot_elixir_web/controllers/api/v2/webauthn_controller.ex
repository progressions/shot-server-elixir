defmodule ShotElixirWeb.Api.V2.WebauthnController do
  @moduledoc """
  Controller for WebAuthn/passkey authentication endpoints.

  Provides endpoints for:
  - Generating registration options
  - Verifying registration responses
  - Generating authentication options
  - Verifying authentication responses
  - Managing user credentials
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Guardian
  alias ShotElixir.Services.WebAuthnService
  alias ShotElixirWeb.AuthHelpers

  # Registration endpoints (require authentication)

  @doc """
  POST /api/v2/webauthn/register/options

  Generates registration options for the authenticated user to register a new passkey.
  """
  def registration_options(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    {:ok, options} = WebAuthnService.generate_registration_options(user)

    conn
    |> put_status(:ok)
    |> json(options)
  end

  @doc """
  POST /api/v2/webauthn/register/verify

  Verifies a registration response and stores the new credential.

  Expected params:
  - attestationObject: Base64url encoded attestation object
  - clientDataJSON: Base64url encoded client data JSON
  - challengeId: ID of the stored challenge
  - name: User-provided name for the passkey
  """
  def verify_registration(conn, params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, attestation_object} <- get_required_param(params, "attestationObject"),
         {:ok, client_data_json} <- get_required_param(params, "clientDataJSON"),
         {:ok, challenge_id} <- get_required_param(params, "challengeId"),
         {:ok, name} <- get_required_param(params, "name"),
         {:ok, credential} <-
           WebAuthnService.verify_registration(
             user,
             attestation_object,
             client_data_json,
             challenge_id,
             name
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        id: credential.id,
        name: credential.name,
        created_at: DateTime.to_iso8601(credential.inserted_at)
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  # Authentication endpoints (public)

  @doc """
  POST /api/v2/webauthn/authenticate/options

  Generates authentication options for a user to authenticate with a passkey.

  Expected params:
  - email: The user's email address
  """
  def authentication_options(conn, %{"email" => email}) do
    case WebAuthnService.generate_authentication_options(email) do
      {:ok, options} ->
        conn
        |> put_status(:ok)
        |> json(options)

      {:error, :no_passkeys_registered} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No passkeys registered for this account"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  def authentication_options(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Email is required"})
  end

  @doc """
  POST /api/v2/webauthn/authenticate/verify

  Verifies an authentication response and returns a JWT token.

  Expected params:
  - credentialId: Base64url encoded credential ID
  - authenticatorData: Base64url encoded authenticator data
  - signature: Base64url encoded signature
  - clientDataJSON: Base64url encoded client data JSON
  - challengeId: ID of the stored challenge
  """
  def verify_authentication(conn, params) do
    with {:ok, credential_id} <- get_required_param(params, "credentialId"),
         {:ok, authenticator_data} <- get_required_param(params, "authenticatorData"),
         {:ok, signature} <- get_required_param(params, "signature"),
         {:ok, client_data_json} <- get_required_param(params, "clientDataJSON"),
         {:ok, challenge_id} <- get_required_param(params, "challengeId"),
         {:ok, user} <-
           WebAuthnService.verify_authentication(
             credential_id,
             authenticator_data,
             signature,
             client_data_json,
             challenge_id
           ) do
      # Generate JWT token using shared helper
      {token, _user_json} = AuthHelpers.generate_auth_response(user)

      conn
      |> put_resp_header("authorization", "Bearer #{token}")
      |> put_resp_header("access-control-expose-headers", "Authorization")
      |> put_status(:ok)
      |> json(%{
        user: AuthHelpers.render_user(user),
        token: token
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: format_error(reason)})
    end
  end

  # Credential management endpoints (require authentication)

  @doc """
  GET /api/v2/webauthn/credentials

  Lists all passkey credentials for the authenticated user.
  """
  def list_credentials(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    credentials = WebAuthnService.list_credentials(user)

    conn
    |> put_status(:ok)
    |> json(%{
      credentials:
        Enum.map(credentials, fn cred ->
          %{
            id: cred.id,
            name: cred.name,
            created_at: DateTime.to_iso8601(cred.inserted_at),
            last_used_at: format_optional_datetime(cred.last_used_at),
            backed_up: cred.backed_up
          }
        end)
    })
  end

  @doc """
  DELETE /api/v2/webauthn/credentials/:id

  Deletes a passkey credential.
  """
  def delete_credential(conn, %{"id" => credential_id}) do
    user = Guardian.Plug.current_resource(conn)

    case WebAuthnService.delete_credential(user, credential_id) do
      {:ok, _credential} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Passkey deleted successfully"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Passkey not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  @doc """
  PATCH /api/v2/webauthn/credentials/:id

  Renames a passkey credential.

  Expected params:
  - name: New name for the passkey
  """
  def update_credential(conn, %{"id" => credential_id, "name" => name}) do
    user = Guardian.Plug.current_resource(conn)

    case WebAuthnService.rename_credential(user, credential_id, name) do
      {:ok, credential} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: credential.id,
          name: credential.name,
          created_at: DateTime.to_iso8601(credential.inserted_at),
          last_used_at: format_optional_datetime(credential.last_used_at)
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Passkey not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: format_error(reason)})
    end
  end

  def update_credential(conn, %{"id" => _}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Name is required"})
  end

  # Private helper functions

  defp get_required_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "#{key} is required"}
      "" -> {:error, "#{key} cannot be empty"}
      value -> {:ok, value}
    end
  end

  defp format_error(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp format_optional_datetime(nil), do: nil
  defp format_optional_datetime(datetime), do: DateTime.to_iso8601(datetime)
end
