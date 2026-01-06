defmodule ShotElixir.AI.Providers.GeminiProvider do
  @moduledoc """
  Google Gemini AI provider implementation.

  Uses OAuth2 authentication with Google Cloud.
  Supports:
    - Chat completions via Gemini Pro model
    - Image generation via Imagen model

  ## OAuth Flow
  Users authenticate via Google OAuth through the frontend.
  Tokens are stored encrypted in the AiCredentials system.
  Token refresh is handled automatically when tokens expire.

  ## Implementation Status
  This provider is partially implemented - OAuth token handling
  is functional, but the actual API calls will be completed
  when the frontend OAuth flow is ready.
  """

  @behaviour ShotElixir.AI.Provider

  require Logger

  import Ecto.Query, only: [from: 2]

  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential
  alias ShotElixir.Repo

  @base_url "https://generativelanguage.googleapis.com"
  @default_max_tokens 4096
  @chat_model "gemini-1.5-pro"

  @impl true
  def send_chat_request(%AiCredential{} = credential, prompt, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    Logger.info("GeminiProvider: Sending chat request with max_tokens: #{max_tokens}")

    with {:ok, credential} <- ensure_valid_token(credential),
         {:ok, access_token} <- get_access_token(credential) do
      payload = %{
        contents: [%{parts: [%{text: prompt}]}],
        generationConfig: %{
          maxOutputTokens: max_tokens
        }
      }

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ]

      url = "#{@base_url}/v1beta/models/#{@chat_model}:generateContent"

      case Req.post(url,
             json: payload,
             headers: headers,
             receive_timeout: 120_000,
             connect_options: [timeout: 30_000]
           ) do
        {:ok, %{status: 200, body: response}} ->
          Logger.info("GeminiProvider: Chat request successful")
          # Transform Gemini response format to match Grok/OpenAI format
          transform_chat_response(response)

        {:ok, %{status: status, body: body}} ->
          handle_error_response(status, body)

        {:error, reason} ->
          Logger.error("GeminiProvider: HTTP request failed: #{inspect(reason)}")
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def generate_images(%AiCredential{} = credential, prompt, num_images, _opts \\ []) do
    # Gemini's Imagen API for image generation
    Logger.info("GeminiProvider: Generating #{num_images} images")

    with {:ok, credential} <- ensure_valid_token(credential),
         {:ok, access_token} <- get_access_token(credential) do
      payload = %{
        instances: [%{prompt: prompt}],
        parameters: %{
          sampleCount: min(num_images, 4)
        }
      }

      headers = [
        {"Authorization", "Bearer #{access_token}"},
        {"Content-Type", "application/json"}
      ]

      # Imagen endpoint through Vertex AI
      # Note: This requires Vertex AI setup - may need adjustment
      url = "#{@base_url}/v1beta/models/imagen-3.0-generate-001:predict"

      case Req.post(url,
             json: payload,
             headers: headers,
             receive_timeout: 120_000,
             connect_options: [timeout: 30_000]
           ) do
        {:ok, %{status: 200, body: response}} ->
          extract_image_data(response, num_images)

        {:ok, %{status: status, body: body}} ->
          handle_error_response(status, body)

        {:error, reason} ->
          Logger.error("GeminiProvider: Image generation HTTP request failed: #{inspect(reason)}")
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def validate_credential(%AiCredential{provider: "gemini"} = credential) do
    case credential.token_expires_at do
      nil ->
        # No expiration set - check if we have tokens
        if has_valid_tokens?(credential) do
          {:ok, credential}
        else
          {:error, :invalid}
        end

      expires_at ->
        now = DateTime.utc_now()

        if DateTime.compare(expires_at, now) == :gt do
          {:ok, credential}
        else
          # Token is expired - need refresh
          {:error, :expired}
        end
    end
  end

  def validate_credential(_), do: {:error, :invalid}

  # Private functions

  defp has_valid_tokens?(credential) do
    case AiCredentials.get_decrypted_access_token(credential) do
      {:ok, token} when is_binary(token) and byte_size(token) > 0 -> true
      _ -> false
    end
  end

  defp ensure_valid_token(credential) do
    case validate_credential(credential) do
      {:ok, cred} ->
        {:ok, cred}

      {:error, :expired} ->
        # Attempt to refresh the token
        refresh_token(credential)

      {:error, :invalid} ->
        {:error, :invalid_credential}
    end
  end

  # Use database-level locking to prevent concurrent token refresh race conditions.
  # Multiple requests may simultaneously detect an expired token - this ensures
  # only one actually performs the refresh while others wait and get the new token.
  defp refresh_token(credential) do
    Repo.transaction(fn ->
      # Acquire row lock - other processes will wait here
      locked_credential =
        from(c in AiCredential,
          where: c.id == ^credential.id,
          lock: "FOR UPDATE"
        )
        |> Repo.one()

      case locked_credential do
        nil ->
          Repo.rollback(:credential_not_found)

        cred ->
          # Re-check if token is still expired - another process may have refreshed it
          if token_still_expired?(cred) do
            do_refresh_token(cred)
          else
            # Token was refreshed by another process, use the updated credential
            Logger.info("GeminiProvider: Token already refreshed by concurrent request")
            {:ok, cred}
          end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp token_still_expired?(credential) do
    case credential.token_expires_at do
      nil -> true
      expires_at -> DateTime.compare(expires_at, DateTime.utc_now()) != :gt
    end
  end

  defp do_refresh_token(credential) do
    case AiCredentials.get_decrypted_refresh_token(credential) do
      {:ok, refresh_token} when is_binary(refresh_token) and byte_size(refresh_token) > 0 ->
        # Call Google's token refresh endpoint
        payload = %{
          grant_type: "refresh_token",
          refresh_token: refresh_token,
          client_id: google_client_id(),
          client_secret: google_client_secret()
        }

        case Req.post("https://oauth2.googleapis.com/token",
               form: payload,
               receive_timeout: 30_000
             ) do
          {:ok, %{status: 200, body: body}} ->
            # Update the credential with new tokens
            update_tokens_from_refresh(credential, body)

          {:ok, %{status: _, body: body}} ->
            Logger.error("GeminiProvider: Token refresh failed: #{inspect(body)}")
            {:error, :token_refresh_failed}

          {:error, reason} ->
            Logger.error("GeminiProvider: Token refresh HTTP error: #{inspect(reason)}")
            {:error, :token_refresh_failed}
        end

      _ ->
        Logger.error("GeminiProvider: No refresh token available")
        {:error, :invalid_credential}
    end
  end

  defp update_tokens_from_refresh(credential, %{"access_token" => new_access_token} = body) do
    expires_in = body["expires_in"] || 3600
    new_expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    attrs = %{
      "access_token" => new_access_token,
      "token_expires_at" => new_expires_at
    }

    # Include new refresh token if provided
    attrs =
      if body["refresh_token"] do
        Map.put(attrs, "refresh_token", body["refresh_token"])
      else
        attrs
      end

    case AiCredentials.update_credential(credential, attrs) do
      {:ok, updated_credential} ->
        Logger.info("GeminiProvider: Token refreshed successfully")
        {:ok, updated_credential}

      {:error, _} ->
        {:error, :token_refresh_failed}
    end
  end

  defp update_tokens_from_refresh(_, _), do: {:error, :token_refresh_failed}

  defp get_access_token(%AiCredential{} = credential) do
    case AiCredentials.get_decrypted_access_token(credential) do
      {:ok, token} when is_binary(token) and byte_size(token) > 0 ->
        {:ok, token}

      _ ->
        Logger.error("GeminiProvider: Failed to decrypt access token")
        {:error, :invalid_credential}
    end
  end

  defp handle_error_response(status, body) do
    error_message = extract_error_message(body)

    cond do
      status == 429 ->
        Logger.warning("GeminiProvider: Rate limited: #{error_message}")
        {:error, :rate_limited, error_message}

      status >= 500 ->
        Logger.error("GeminiProvider: Server error (#{status}): #{error_message}")
        {:error, :server_error, error_message}

      status == 401 || status == 403 ->
        Logger.error("GeminiProvider: Authentication error: #{error_message}")
        {:error, :invalid_credential}

      true ->
        Logger.error("GeminiProvider: Request failed with status #{status}: #{error_message}")
        {:error, error_message}
    end
  end

  defp extract_error_message(body) when is_map(body) do
    cond do
      is_binary(body["error"]) -> body["error"]
      is_map(body["error"]) && is_binary(body["error"]["message"]) -> body["error"]["message"]
      true -> inspect(body)
    end
  end

  defp extract_error_message(body), do: inspect(body)

  # Transform Gemini response to match Grok/OpenAI format for consistency
  defp transform_chat_response(%{"candidates" => [candidate | _]} = _response) do
    content = get_in(candidate, ["content", "parts", Access.at(0), "text"]) || ""
    finish_reason = candidate["finishReason"]

    # Transform to OpenAI-compatible format
    transformed = %{
      "choices" => [
        %{
          "message" => %{"content" => content},
          "finish_reason" => transform_finish_reason(finish_reason)
        }
      ]
    }

    {:ok, transformed}
  end

  defp transform_chat_response(_), do: {:error, "Unexpected response format"}

  defp transform_finish_reason("STOP"), do: "stop"
  defp transform_finish_reason("MAX_TOKENS"), do: "length"
  defp transform_finish_reason("SAFETY"), do: "content_filter"
  defp transform_finish_reason(_), do: "stop"

  defp extract_image_data(%{"predictions" => predictions}, num_images)
       when is_list(predictions) do
    urls =
      predictions
      |> Enum.take(num_images)
      |> Enum.map(fn pred ->
        # Gemini returns base64 encoded images
        case pred["bytesBase64Encoded"] do
          nil -> nil
          b64_data -> "data:image/png;base64,#{b64_data}"
        end
      end)
      |> Enum.reject(&is_nil/1)

    case urls do
      [] -> {:error, "No images generated"}
      [url] when num_images == 1 -> {:ok, url}
      urls -> {:ok, urls}
    end
  end

  defp extract_image_data(_, _), do: {:error, "Unexpected image response format"}

  # Config helpers
  defp google_client_id do
    fetch_google_oauth_config_value!(
      :client_id,
      "GOOGLE_CLIENT_ID",
      "Google OAuth client_id is not configured. " <>
        "Set :google_oauth, :client_id in config or the GOOGLE_CLIENT_ID environment variable."
    )
  end

  defp google_client_secret do
    fetch_google_oauth_config_value!(
      :client_secret,
      "GOOGLE_CLIENT_SECRET",
      "Google OAuth client_secret is not configured. " <>
        "Set :google_oauth, :client_secret in config or the GOOGLE_CLIENT_SECRET environment variable."
    )
  end

  defp fetch_google_oauth_config_value!(key, env_var, error_message) do
    config = Application.get_env(:shot_elixir, :google_oauth) || []

    case Keyword.get(config, key) || System.get_env(env_var) do
      nil ->
        raise ArgumentError, error_message

      "" ->
        raise ArgumentError, error_message

      value ->
        value
    end
  end
end
