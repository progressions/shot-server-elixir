defmodule ShotElixir.Services.GrokService do
  @moduledoc """
  Service for interacting with Grok (xAI) API for AI image generation.
  """

  require Logger

  @base_url "https://api.x.ai"
  @max_prompt_length 1024

  @doc """
  Sends a chat completion request to Grok API.

  ## Parameters
    - prompt: Text prompt for the AI
    - max_tokens: Maximum tokens in response (default 2048)

  ## Returns
    - {:ok, response_map} on success
    - {:error, reason} on failure

  ## Examples
      iex> send_request("Generate a character...", 1000)
      {:ok, %{"choices" => [%{"message" => %{"content" => "..."}}]}}
  """
  def send_request(prompt, max_tokens \\ 2048) do
    if disabled?() do
      Logger.info("Grok API disabled in test mode, returning mock response")

      {:ok,
       %{
         "choices" => [
           %{"message" => %{"content" => "Mock response for: #{String.slice(prompt, 0, 50)}..."}}
         ]
       }}
    else
      do_send_request(prompt, max_tokens)
    end
  end

  defp do_send_request(prompt, max_tokens) do
    Logger.info("Sending Grok API request with max_tokens: #{max_tokens}")
    Logger.debug("Prompt length: #{String.length(prompt)} characters")

    payload = %{
      model: "grok-4",
      messages: [%{role: "user", content: prompt}],
      max_tokens: max_tokens
    }

    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    Logger.info("Making request to #{@base_url}/v1/chat/completions")

    # AI requests can take a while, set a longer timeout (2 minutes)
    # Also set connect_timeout for initial connection
    case Req.post("#{@base_url}/v1/chat/completions",
           json: payload,
           headers: headers,
           receive_timeout: 120_000,
           connect_options: [timeout: 30_000]
         ) do
      {:ok, %{status: 200, body: response}} ->
        Logger.info("Grok API request successful")
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        handle_error_response(status, body)

      {:error, reason} ->
        Logger.error("Grok API HTTP request failed: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates images using Grok's image generation API.

  ## Parameters
    - prompt: Text description for image generation
    - num_images: Number of images to generate (1-10, default 3)
    - response_format: "url" or "b64_json" (default "url")

  ## Returns
    - Single URL string when num_images is 1
    - List of URL strings when num_images > 1
    - {:error, reason} on failure

  ## Examples
      iex> generate_image("A cyberpunk warrior", 3, "url")
      ["https://...", "https://...", "https://..."]
  """
  def generate_image(prompt, num_images \\ 3, response_format \\ "url") do
    if disabled?() do
      Logger.info("Grok API disabled in test mode, returning mock image URL")
      mock_url = "https://example.com/mock-grok-image.png"
      if num_images == 1, do: mock_url, else: List.duplicate(mock_url, num_images)
    else
      do_generate_image(prompt, num_images, response_format)
    end
  end

  defp do_generate_image(prompt, num_images, response_format) do
    # Truncate prompt if too long
    truncated_prompt = String.slice(prompt, 0, @max_prompt_length)

    if String.length(prompt) > @max_prompt_length do
      Logger.warning("Prompt truncated to #{@max_prompt_length} characters for image generation")
    end

    payload = %{
      model: "grok-2-image-1212",
      prompt: truncated_prompt,
      n: clamp(num_images, 1, 10),
      response_format: response_format
    }

    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    # Image generation can take a while, set a longer timeout (2 minutes)
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
        Logger.error("Grok image generation HTTP request failed: #{inspect(reason)}")
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Handle error responses with specific classification for credit exhaustion
  defp handle_error_response(status, body) do
    error_message = extract_error_message(body)

    cond do
      status == 429 && credit_exhausted?(body) ->
        Logger.error("Grok API credits exhausted: #{error_message}")
        {:error, :credit_exhausted, error_message}

      status == 429 ->
        Logger.warning("Grok API rate limited: #{error_message}")
        {:error, :rate_limited, error_message}

      status >= 500 ->
        Logger.error("Grok API server error (#{status}): #{error_message}")
        {:error, :server_error, error_message}

      true ->
        Logger.error("Grok API request failed with status #{status}: #{error_message}")
        {:error, error_message}
    end
  end

  # Check if 429 error is due to credit exhaustion vs rate limiting
  defp credit_exhausted?(body) when is_map(body) do
    error = body["error"] || ""

    error_str =
      if is_binary(error) do
        error
      else
        inspect(error)
      end

    # Use case-insensitive matching for reliable detection
    error_str_lower = String.downcase(error_str)

    String.contains?(error_str_lower, "credits") ||
      String.contains?(error_str_lower, "spending limit") ||
      String.contains?(error_str_lower, "exhausted")
  end

  defp credit_exhausted?(_), do: false

  # Extract human-readable error message from response body
  defp extract_error_message(body) when is_map(body) do
    cond do
      is_binary(body["error"]) -> body["error"]
      is_map(body["error"]) && is_binary(body["error"]["message"]) -> body["error"]["message"]
      true -> inspect(body)
    end
  end

  defp extract_error_message(body), do: inspect(body)

  # Extract image URLs or base64 data from response
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

        # Check for errors
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

  # Check if Grok API is disabled (e.g., in test environment)
  defp disabled? do
    Application.get_env(:shot_elixir, :grok)[:disabled] == true
  end

  # Get API key from config
  defp api_key do
    key =
      Application.get_env(:shot_elixir, :grok)[:api_key] ||
        System.get_env("GROK_API_KEY")

    if is_nil(key) || key == "" do
      Logger.error("Grok API key not configured!")
      raise "Grok API key not configured"
    end

    Logger.debug("Grok API key loaded: #{String.slice(key, 0..10)}...")
    key
  end

  # Clamp value between min and max
  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
