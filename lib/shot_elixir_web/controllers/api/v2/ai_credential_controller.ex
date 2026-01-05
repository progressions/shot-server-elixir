defmodule ShotElixirWeb.Api.V2.AiCredentialController do
  @moduledoc """
  Controller for managing AI provider credentials.

  Handles CRUD operations for API keys (Grok, OpenAI) and
  OAuth tokens (Gemini). All credentials are stored encrypted
  and API keys are only returned in masked form.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.AiCredentials
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  plug :put_view, ShotElixirWeb.Api.V2.AiCredentialView

  @doc """
  GET /api/v2/ai_credentials

  Lists all AI credentials for the current user.
  API keys are returned masked (only last 8 characters visible).
  """
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)
    credentials = AiCredentials.list_credentials_for_user(current_user.id)
    render(conn, :index, ai_credentials: credentials)
  end

  @doc """
  POST /api/v2/ai_credentials

  Creates a new AI credential for the current user.

  For Grok/OpenAI: expects `provider` and `api_key`
  For Gemini: expects `provider`, `access_token`, `refresh_token`, and `token_expires_at`
  """
  def create(conn, %{"ai_credential" => credential_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    attrs =
      credential_params
      |> Map.put("user_id", current_user.id)

    case AiCredentials.create_credential(attrs) do
      {:ok, credential} ->
        conn
        |> put_status(:created)
        |> render(:show, ai_credential: credential)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  @doc """
  PUT /api/v2/ai_credentials/:id

  Updates an existing AI credential.
  Only the credential owner can update it.
  """
  def update(conn, %{"id" => id, "ai_credential" => credential_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_user_credential(current_user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Credential not found"})

      credential ->
        case AiCredentials.update_credential(credential, credential_params) do
          {:ok, updated_credential} ->
            render(conn, :show, ai_credential: updated_credential)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> put_view(ShotElixirWeb.ChangesetView)
            |> render(:error, changeset: changeset)
        end
    end
  end

  @doc """
  DELETE /api/v2/ai_credentials/:id

  Deletes an AI credential.
  Only the credential owner can delete it.
  """
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_user_credential(current_user.id, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Credential not found"})

      credential ->
        case AiCredentials.delete_credential(credential) do
          {:ok, _deleted} ->
            send_resp(conn, :no_content, "")

          {:error, _reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete credential"})
        end
    end
  end

  # Private helpers

  # Gets a credential only if it belongs to the specified user
  defp get_user_credential(user_id, credential_id) do
    case AiCredentials.get_credential(credential_id) do
      nil -> nil
      credential when credential.user_id == user_id -> credential
      _credential -> nil
    end
  end
end
