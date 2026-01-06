defmodule ShotElixirWeb.GoogleOAuthController do
  @moduledoc """
  Handles Google OAuth2 flow for Gemini AI provider integration.

  ## Flow
  1. User clicks "Connect with Google" in frontend
  2. Frontend redirects to GET /auth/google with user_id param
  3. This controller redirects to Google OAuth consent screen
  4. User grants permission, Google redirects to GET /auth/google/callback
  5. Controller exchanges code for tokens, stores them, redirects to frontend
  """

  use ShotElixirWeb, :controller

  require Logger

  alias ShotElixir.AiCredentials

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"

  # Scopes needed for Gemini API
  @scopes [
    "https://www.googleapis.com/auth/generative-language.tuning",
    "https://www.googleapis.com/auth/generative-language.retriever"
  ]

  @doc """
  Initiates the Google OAuth flow.

  Requires `user_id` query parameter to associate the credential with the user.
  Redirects to Google's OAuth consent screen.
  """
  def authorize(conn, %{"user_id" => user_id}) do
    state = generate_state(user_id)

    params = %{
      client_id: google_client_id(),
      redirect_uri: callback_url(),
      response_type: "code",
      scope: Enum.join(@scopes, " "),
      access_type: "offline",
      prompt: "consent",
      state: state
    }

    auth_url = "#{@google_auth_url}?#{URI.encode_query(params)}"

    Logger.info("GoogleOAuth: Redirecting user #{user_id} to Google OAuth")

    redirect(conn, external: auth_url)
  end

  def authorize(conn, _params) do
    Logger.warning("GoogleOAuth: Missing user_id parameter")

    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing user_id parameter"})
  end

  @doc """
  Handles the OAuth callback from Google.

  Exchanges the authorization code for access and refresh tokens,
  then stores them encrypted in the database.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    with {:ok, user_id} <- verify_state(state),
         {:ok, tokens} <- exchange_code_for_tokens(code),
         {:ok, _credential} <- store_tokens(user_id, tokens) do
      Logger.info("GoogleOAuth: Successfully stored tokens for user #{user_id}")

      # Redirect to frontend settings page with success
      redirect(conn, external: frontend_redirect_url("success"))
    else
      {:error, :invalid_state} ->
        Logger.warning("GoogleOAuth: Invalid state parameter")
        redirect(conn, external: frontend_redirect_url("error", "Invalid state"))

      {:error, :token_exchange_failed, reason} ->
        Logger.error("GoogleOAuth: Token exchange failed: #{inspect(reason)}")
        redirect(conn, external: frontend_redirect_url("error", "Failed to get tokens"))

      {:error, reason} ->
        Logger.error("GoogleOAuth: Failed to store tokens: #{inspect(reason)}")
        redirect(conn, external: frontend_redirect_url("error", "Failed to save credentials"))
    end
  end

  def callback(conn, %{"error" => error, "error_description" => description}) do
    Logger.warning("GoogleOAuth: User denied access: #{error} - #{description}")
    redirect(conn, external: frontend_redirect_url("error", description))
  end

  def callback(conn, params) do
    Logger.warning("GoogleOAuth: Unexpected callback params: #{inspect(params)}")
    redirect(conn, external: frontend_redirect_url("error", "Unexpected response"))
  end

  # Private functions

  defp generate_state(user_id) do
    # Encode user_id with a signature to prevent tampering
    timestamp = System.system_time(:second)
    data = "#{user_id}:#{timestamp}"
    signature = :crypto.mac(:hmac, :sha256, state_secret(), data) |> Base.url_encode64()
    Base.url_encode64("#{data}:#{signature}")
  end

  defp verify_state(state) do
    with {:ok, decoded} <- Base.url_decode64(state),
         [user_id, timestamp_str, signature] <- String.split(decoded, ":"),
         {timestamp, ""} <- Integer.parse(timestamp_str),
         true <- valid_timestamp?(timestamp),
         true <- valid_signature?(user_id, timestamp_str, signature) do
      {:ok, user_id}
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp valid_timestamp?(timestamp) do
    # State is valid for 10 minutes
    current = System.system_time(:second)
    current - timestamp < 600
  end

  defp valid_signature?(user_id, timestamp, signature) do
    data = "#{user_id}:#{timestamp}"
    expected = :crypto.mac(:hmac, :sha256, state_secret(), data) |> Base.url_encode64()
    Plug.Crypto.secure_compare(expected, signature)
  end

  defp exchange_code_for_tokens(code) do
    body = %{
      code: code,
      client_id: google_client_id(),
      client_secret: google_client_secret(),
      redirect_uri: callback_url(),
      grant_type: "authorization_code"
    }

    case Req.post(@google_token_url, form: body) do
      {:ok, %{status: 200, body: response}} ->
        {:ok,
         %{
           access_token: response["access_token"],
           refresh_token: response["refresh_token"],
           expires_in: response["expires_in"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, :token_exchange_failed, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, :token_exchange_failed, reason}
    end
  end

  defp store_tokens(user_id, tokens) do
    expires_at =
      if tokens.expires_in do
        DateTime.add(DateTime.utc_now(), tokens.expires_in, :second)
      else
        nil
      end

    # Check if credential already exists
    case AiCredentials.get_credential_by_user_and_provider(user_id, "gemini") do
      nil ->
        # Create new credential
        AiCredentials.create_credential(%{
          "user_id" => user_id,
          "provider" => "gemini",
          "access_token" => tokens.access_token,
          "refresh_token" => tokens.refresh_token,
          "token_expires_at" => expires_at
        })

      existing ->
        # Update existing credential
        AiCredentials.update_credential(existing, %{
          "access_token" => tokens.access_token,
          "refresh_token" => tokens.refresh_token,
          "token_expires_at" => expires_at,
          "status" => "active",
          "status_message" => nil
        })
    end
  end

  defp frontend_redirect_url(status, message \\ nil) do
    base_url = frontend_url()
    params = %{oauth: "gemini", status: status}

    params =
      if message do
        Map.put(params, :message, message)
      else
        params
      end

    "#{base_url}/settings?#{URI.encode_query(params)}"
  end

  # Configuration helpers

  defp google_client_id do
    config = Application.get_env(:shot_elixir, :google_oauth) || []

    case Keyword.get(config, :client_id) || System.get_env("GOOGLE_CLIENT_ID") do
      nil ->
        raise ArgumentError,
              "Google OAuth client_id is not configured. " <>
                "Set :google_oauth, :client_id in config or GOOGLE_CLIENT_ID env var."

      "" ->
        raise ArgumentError, "Google OAuth client_id cannot be empty."

      value ->
        value
    end
  end

  defp google_client_secret do
    config = Application.get_env(:shot_elixir, :google_oauth) || []

    case Keyword.get(config, :client_secret) || System.get_env("GOOGLE_CLIENT_SECRET") do
      nil ->
        raise ArgumentError,
              "Google OAuth client_secret is not configured. " <>
                "Set :google_oauth, :client_secret in config or GOOGLE_CLIENT_SECRET env var."

      "" ->
        raise ArgumentError, "Google OAuth client_secret cannot be empty."

      value ->
        value
    end
  end

  defp callback_url do
    config = Application.get_env(:shot_elixir, :google_oauth) || []

    Keyword.get(config, :callback_url) ||
      System.get_env("GOOGLE_OAUTH_CALLBACK_URL") ||
      "#{host_url()}/auth/google/callback"
  end

  defp frontend_url do
    config = Application.get_env(:shot_elixir, :google_oauth) || []
    Keyword.get(config, :frontend_url) || System.get_env("FRONTEND_URL") || "https://chiwar.net"
  end

  defp host_url do
    config = Application.get_env(:shot_elixir, ShotElixirWeb.Endpoint) || []
    url_config = Keyword.get(config, :url) || []
    host = Keyword.get(url_config, :host) || "localhost"
    port = Keyword.get(url_config, :port) || 4002
    scheme = Keyword.get(url_config, :scheme) || "http"

    if port in [80, 443] do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end

  defp state_secret do
    config = Application.get_env(:shot_elixir, ShotElixirWeb.Endpoint) || []
    Keyword.get(config, :secret_key_base) || raise "secret_key_base not configured"
  end
end
