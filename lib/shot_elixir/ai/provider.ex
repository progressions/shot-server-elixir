defmodule ShotElixir.AI.Provider do
  @moduledoc """
  Behaviour defining the interface for AI providers.

  All AI providers (Grok, OpenAI, Gemini) must implement this behaviour.
  This allows the AiService to use any configured provider transparently.

  ## Provider Types
    - `:grok` - xAI Grok API (API key authentication)
    - `:openai` - OpenAI API (API key authentication)
    - `:gemini` - Google Gemini API (OAuth authentication)

  ## Implementing a Provider
  Providers must implement:
    - `send_chat_request/3` - Send a chat completion request
    - `generate_images/4` - Generate images from a prompt
    - `validate_credential/1` - Validate that a credential is usable
  """

  alias ShotElixir.AiCredentials.AiCredential

  @type provider :: :grok | :openai | :gemini
  @type chat_response :: {:ok, map()} | {:error, term()}
  @type image_response :: {:ok, String.t() | [String.t()]} | {:error, term()}

  @doc """
  Sends a chat completion request to the AI provider.

  ## Parameters
    - credential: The AiCredential containing authentication details
    - prompt: Text prompt for the AI
    - opts: Provider-specific options (max_tokens, model, etc.)

  ## Returns
    - `{:ok, response_map}` on success
    - `{:error, reason}` on failure
    - `{:error, :credit_exhausted, message}` when API credits are exhausted
    - `{:error, :rate_limited, message}` when rate limited
    - `{:error, :invalid_credential}` when credential is invalid/expired
  """
  @callback send_chat_request(
              credential :: AiCredential.t(),
              prompt :: String.t(),
              opts :: keyword()
            ) ::
              chat_response()

  @doc """
  Generates images using the AI provider's image generation API.

  ## Parameters
    - credential: The AiCredential containing authentication details
    - prompt: Text description for image generation
    - num_images: Number of images to generate (1-10)
    - opts: Provider-specific options (response_format, size, etc.)

  ## Returns
    - `{:ok, url}` when generating a single image
    - `{:ok, [urls]}` when generating multiple images
    - `{:error, reason}` on failure
    - `{:error, :credit_exhausted, message}` when API credits are exhausted
  """
  @callback generate_images(
              credential :: AiCredential.t(),
              prompt :: String.t(),
              num_images :: pos_integer(),
              opts :: keyword()
            ) :: image_response()

  @doc """
  Validates that a credential is usable for API requests.

  For API key providers, this might check if the key format is valid.
  For OAuth providers, this checks if the token is not expired.

  ## Parameters
    - credential: The AiCredential to validate

  ## Returns
    - `{:ok, credential}` if valid
    - `{:error, :expired}` if OAuth token is expired
    - `{:error, :invalid}` if credential is malformed
  """
  @callback validate_credential(credential :: AiCredential.t()) ::
              {:ok, AiCredential.t()} | {:error, :expired | :invalid}

  @doc """
  Returns the appropriate provider module for a given provider atom.
  """
  @spec provider_module(provider()) :: module()
  def provider_module(:grok), do: ShotElixir.AI.Providers.GrokProvider
  def provider_module(:openai), do: ShotElixir.AI.Providers.OpenAIProvider
  def provider_module(:gemini), do: ShotElixir.AI.Providers.GeminiProvider

  @doc """
  Validates provider atom is supported.
  """
  @spec valid_provider?(term()) :: boolean()
  def valid_provider?(provider) when provider in [:grok, :openai, :gemini], do: true
  def valid_provider?(_), do: false

  @doc """
  Sends a chat request using the appropriate provider for the credential.
  """
  @spec send_chat_request(AiCredential.t(), String.t(), keyword()) :: chat_response()
  def send_chat_request(%AiCredential{provider: provider} = credential, prompt, opts \\ []) do
    module = provider_module(provider)
    module.send_chat_request(credential, prompt, opts)
  end

  @doc """
  Generates images using the appropriate provider for the credential.
  """
  @spec generate_images(AiCredential.t(), String.t(), pos_integer(), keyword()) ::
          image_response()
  def generate_images(
        %AiCredential{provider: provider} = credential,
        prompt,
        num_images,
        opts \\ []
      ) do
    module = provider_module(provider)
    module.generate_images(credential, prompt, num_images, opts)
  end

  @doc """
  Validates a credential using the appropriate provider.
  """
  @spec validate_credential(AiCredential.t()) ::
          {:ok, AiCredential.t()} | {:error, :expired | :invalid}
  def validate_credential(%AiCredential{provider: provider} = credential) do
    module = provider_module(provider)
    module.validate_credential(credential)
  end
end
