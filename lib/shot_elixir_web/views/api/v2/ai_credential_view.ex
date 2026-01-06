defmodule ShotElixirWeb.Api.V2.AiCredentialView do
  @moduledoc """
  View for rendering AI credential responses.

  API keys are always masked - only the last 8 characters are shown.
  Full keys are NEVER returned to the client.
  """

  alias ShotElixir.AiCredentials

  def render("index.json", %{ai_credentials: credentials}) do
    %{ai_credentials: Enum.map(credentials, &render_credential/1)}
  end

  def render("show.json", %{ai_credential: credential}) do
    render_credential(credential)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  defp render_credential(credential) do
    status = credential.status || "active"

    %{
      id: credential.id,
      provider: credential.provider,
      connected: status == "active",
      api_key_hint: AiCredentials.mask_api_key(credential),
      token_expires_at: credential.token_expires_at,
      status: status,
      status_message: credential.status_message,
      status_updated_at: credential.status_updated_at,
      inserted_at: credential.created_at,
      updated_at: credential.updated_at
    }
  end
end
