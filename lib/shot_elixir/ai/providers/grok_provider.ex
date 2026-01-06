defmodule ShotElixir.AI.Providers.GrokProvider do
  @moduledoc """
  Grok (xAI) AI provider implementation.

  Uses API key authentication. Supports:
    - Chat completions via grok-4 model
    - Image generation via grok-2-image-1212 model

  ## Configuration
  Users provide their own Grok API key through the AiCredentials system.
  """

  @behaviour ShotElixir.AI.Provider

  require Logger

  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential

  @base_url "https://api.x.ai"
  @max_prompt_length 1024
  @default_max_tokens 2048
  @chat_model "grok-4"
  @image_model "grok-2-image-1212"

  @impl true
  def send_chat_request(%AiCredential{} = credential, prompt, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    Logger.info("GrokProvider: Sending chat request with max_tokens: #{max_tokens}")
    Logger.debug("Prompt length: #{String.length(prompt)} characters")

    with {:ok, api_key} <- get_api_key(credential) do
      payload = %{
        model: @chat_model,
        messages: [%{role: "user", content: prompt}],
        max_tokens: max_tokens
      }

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      Logger.info("Making request to #{@base_url}/v1/chat/completions")

      case Req.post("#{@base_url}/v1/chat/completions",
             json: payload,
             headers: headers,
             receive_timeout: 120_000,
             connect_options: [timeout: 30_000]
           ) do
        {:ok, %{status: 200, body: response}} ->
          Logger.info("GrokProvider: Chat request successful")
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          handle_error_response(status, body)

        {:error, reason} ->
          Logger.error("GrokProvider: HTTP request failed: #{inspect(reason)}")
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def generate_images(%AiCredential{} = credential, prompt, num_images, opts \\ []) do
    response_format = Keyword.get(opts, :response_format, "url")

    # Truncate prompt if too long
    truncated_prompt = String.slice(prompt, 0, @max_prompt_length)

    if String.length(prompt) > @max_prompt_length do
      Logger.warning("GrokProvider: Prompt truncated to #{@max_prompt_length} characters")
    end

    with {:ok, api_key} <- get_api_key(credential) do
      payload = %{
        model: @image_model,
        prompt: truncated_prompt,
        n: clamp(num_images, 1, 10),
        response_format: response_format
      }

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post("#{@base_url}/v1/images/generations",
             json: payload,
             headers: headers,
             receive_timeout: 120_000,
             connect_options: [timeout: 30_000]
           ) do
        {:ok, %{status: 200, body: response}} ->
          extract_image_data(response, response_format, num_images)

        {:ok, %{status: status, body: body}} ->
          handle_error_response(status, body)

        {:error, reason} ->
          Logger.error("GrokProvider: Image generation HTTP request failed: #{inspect(reason)}")
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def validate_credential(%AiCredential{provider: "grok"} = credential) do
    # For API key providers, check if we can decrypt the key
    case AiCredentials.get_decrypted_api_key(credential) do
      {:ok, key} when is_binary(key) and byte_size(key) > 0 ->
        {:ok, credential}

      _ ->
        {:error, :invalid}
    end
  end

  def validate_credential(_), do: {:error, :invalid}

  # Private functions

  defp get_api_key(%AiCredential{} = credential) do
    case AiCredentials.get_decrypted_api_key(credential) do
      {:ok, key} when is_binary(key) and byte_size(key) > 0 ->
        {:ok, key}

      _ ->
        Logger.error("GrokProvider: Failed to decrypt API key")
        {:error, :invalid_credential}
    end
  end

  defp handle_error_response(status, body) do
    error_message = extract_error_message(body)

    cond do
      status == 429 && credit_exhausted?(body) ->
        Logger.error("GrokProvider: API credits exhausted: #{error_message}")
        {:error, :credit_exhausted, error_message}

      status == 429 ->
        Logger.warning("GrokProvider: Rate limited: #{error_message}")
        {:error, :rate_limited, error_message}

      status >= 500 ->
        Logger.error("GrokProvider: Server error (#{status}): #{error_message}")
        {:error, :server_error, error_message}

      status == 401 ->
        Logger.error("GrokProvider: Invalid API key: #{error_message}")
        {:error, :invalid_credential}

      true ->
        Logger.error("GrokProvider: Request failed with status #{status}: #{error_message}")
        {:error, error_message}
    end
  end

  defp credit_exhausted?(body) when is_map(body) do
    error = body["error"] || ""

    error_str =
      if is_binary(error) do
        error
      else
        inspect(error)
      end

    error_str_lower = String.downcase(error_str)

    String.contains?(error_str_lower, "credits") ||
      String.contains?(error_str_lower, "spending limit") ||
      String.contains?(error_str_lower, "exhausted")
  end

  defp credit_exhausted?(_), do: false

  defp extract_error_message(body) when is_map(body) do
    cond do
      is_binary(body["error"]) -> body["error"]
      is_map(body["error"]) && is_binary(body["error"]["message"]) -> body["error"]["message"]
      true -> inspect(body)
    end
  end

  defp extract_error_message(body), do: inspect(body)

  defp extract_image_data(response, response_format, num_images) do
    case response["data"] do
      nil ->
        {:error, "No image data found in response: #{inspect(response)}"}

      data when is_list(data) ->
        image_data =
          Enum.map(data, fn item ->
            case response_format do
              "b64_json" ->
                case item["b64_json"] do
                  nil -> {:error, "No base64 data in response"}
                  b64_data -> {:ok, "data:image/jpeg;base64,#{b64_data}"}
                end

              "url" ->
                case item["url"] do
                  nil -> {:error, "No image URL in response"}
                  url -> {:ok, url}
                end

              _ ->
                {:error, "Unsupported response format: #{response_format}"}
            end
          end)

        errors =
          Enum.filter(image_data, fn
            {:error, _} -> true
            _ -> false
          end)

        if Enum.empty?(errors) do
          urls = Enum.map(image_data, fn {:ok, url} -> url end)

          if num_images == 1 do
            {:ok, List.first(urls)}
          else
            {:ok, urls}
          end
        else
          {:error, "Failed to extract image data: #{inspect(errors)}"}
        end

      _ ->
        {:error, "Unexpected data format in response"}
    end
  end

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
