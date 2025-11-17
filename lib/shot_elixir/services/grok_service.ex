defmodule ShotElixir.Services.GrokService do
  @moduledoc """
  Service for interacting with Grok (xAI) API for AI image generation.
  """

  require Logger

  @base_url "https://api.x.ai"
  @max_prompt_length 1024

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

    case Req.post("#{@base_url}/v1/images/generations", json: payload, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        extract_image_data(response, response_format, num_images)

      {:ok, %{status: status, body: body}} ->
        {:error, "Request failed with status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

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
        errors = Enum.filter(image_data, fn
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

  # Get API key from config
  defp api_key do
    Application.get_env(:shot_elixir, :grok)[:api_key] ||
      System.get_env("GROK_API_KEY") ||
      raise "Grok API key not configured"
  end

  # Clamp value between min and max
  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end
end
