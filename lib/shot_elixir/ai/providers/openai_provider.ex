defmodule ShotElixir.AI.Providers.OpenAIProvider do
  @moduledoc """
  OpenAI AI provider implementation.

  Uses API key authentication. Supports:
    - Chat completions via gpt-4o model
    - Image generation via dall-e-3 model

  ## Configuration
  Users provide their own OpenAI API key through the AiCredentials system.
  """

  @behaviour ShotElixir.AI.Provider

  require Logger

  alias ShotElixir.AiCredentials
  alias ShotElixir.AiCredentials.AiCredential

  @base_url "https://api.openai.com"
  @default_max_tokens 4096
  @chat_model "gpt-4o"
  @image_model "dall-e-3"

  @impl true
  def send_chat_request(%AiCredential{} = credential, prompt, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    Logger.info("OpenAIProvider: Sending chat request with max_tokens: #{max_tokens}")
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
          Logger.info("OpenAIProvider: Chat request successful")
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          handle_error_response(status, body)

        {:error, reason} ->
          Logger.error("OpenAIProvider: HTTP request failed: #{inspect(reason)}")
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def generate_images(%AiCredential{} = credential, prompt, num_images, opts \\ []) do
    response_format = Keyword.get(opts, :response_format, "url")
    size = Keyword.get(opts, :size, "1024x1024")

    # DALL-E 3 only supports n=1, so we need to make multiple requests
    # For simplicity, we'll just generate one image at a time
    actual_num_images = if num_images > 1, do: min(num_images, 4), else: 1

    with {:ok, api_key} <- get_api_key(credential) do
      results =
        1..actual_num_images
        |> Enum.map(fn _ ->
          generate_single_image(api_key, prompt, response_format, size)
        end)

      # Collect all successful results
      successes =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      errors =
        Enum.filter(results, fn
          {:error, _, _} -> true
          {:error, _} -> true
          _ -> false
        end)

      cond do
        # Return first critical error (credit exhausted, rate limited)
        Enum.any?(errors, fn
          {:error, :credit_exhausted, _} -> true
          {:error, :rate_limited, _} -> true
          _ -> false
        end) ->
          Enum.find(errors, fn
            {:error, :credit_exhausted, _} -> true
            {:error, :rate_limited, _} -> true
            _ -> false
          end)

        Enum.empty?(successes) ->
          List.first(errors) || {:error, "No images generated"}

        length(successes) == 1 && num_images == 1 ->
          {:ok, url} = List.first(successes)
          {:ok, url}

        true ->
          urls = Enum.map(successes, fn {:ok, url} -> url end)
          {:ok, urls}
      end
    end
  end

  defp generate_single_image(api_key, prompt, response_format, size) do
    payload = %{
      model: @image_model,
      prompt: prompt,
      n: 1,
      size: size,
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
        extract_image_data(response, response_format)

      {:ok, %{status: status, body: body}} ->
        handle_error_response(status, body)

      {:error, reason} ->
        Logger.error("OpenAIProvider: Image generation HTTP request failed: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  @impl true
  def validate_credential(%AiCredential{provider: :openai} = credential) do
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
        Logger.error("OpenAIProvider: Failed to decrypt API key")
        {:error, :invalid_credential}
    end
  end

  defp handle_error_response(status, body) do
    error_message = extract_error_message(body)

    cond do
      status == 429 && quota_exceeded?(body) ->
        Logger.error("OpenAIProvider: Quota exceeded: #{error_message}")
        {:error, :credit_exhausted, error_message}

      status == 429 ->
        Logger.warning("OpenAIProvider: Rate limited: #{error_message}")
        {:error, :rate_limited, error_message}

      status >= 500 ->
        Logger.error("OpenAIProvider: Server error (#{status}): #{error_message}")
        {:error, :server_error, error_message}

      status == 401 ->
        Logger.error("OpenAIProvider: Invalid API key: #{error_message}")
        {:error, :invalid_credential}

      true ->
        Logger.error("OpenAIProvider: Request failed with status #{status}: #{error_message}")
        {:error, error_message}
    end
  end

  defp quota_exceeded?(body) when is_map(body) do
    error = get_in(body, ["error", "type"]) || ""
    String.contains?(String.downcase(error), "insufficient_quota")
  end

  defp quota_exceeded?(_), do: false

  defp extract_error_message(body) when is_map(body) do
    cond do
      is_binary(body["error"]) -> body["error"]
      is_map(body["error"]) && is_binary(body["error"]["message"]) -> body["error"]["message"]
      true -> inspect(body)
    end
  end

  defp extract_error_message(body), do: inspect(body)

  defp extract_image_data(response, response_format) do
    case response["data"] do
      nil ->
        {:error, "No image data found in response"}

      [item | _] ->
        case response_format do
          "b64_json" ->
            case item["b64_json"] do
              nil -> {:error, "No base64 data in response"}
              b64_data -> {:ok, "data:image/png;base64,#{b64_data}"}
            end

          "url" ->
            case item["url"] do
              nil -> {:error, "No image URL in response"}
              url -> {:ok, url}
            end

          _ ->
            {:error, "Unsupported response format: #{response_format}"}
        end

      [] ->
        {:error, "Empty image data in response"}
    end
  end
end
