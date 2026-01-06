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

  alias ShotElixir.Accounts
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

  Requires `user_id` query parameter (UUID) to associate the credential with the user.
  Redirects to Google's OAuth consent screen.

  ## Security Notes

  This endpoint is exposed as an unauthenticated route so users can start the OAuth
  flow from the frontend settings page. The `user_id` must be a valid UUID of an
  existing user in the database.

  The frontend is responsible for ensuring that:
  - Only authenticated users can trigger this endpoint
  - The `user_id` comes from the authenticated session, not user input

  The `state` parameter is HMAC-signed with a timestamp to prevent CSRF attacks
  and replay attacks (valid for 10 minutes).
  """
  def authorize(conn, %{"user_id" => user_id}) do
    case Ecto.UUID.cast(user_id) do
      {:ok, valid_user_id} ->
        state = generate_state(valid_user_id)

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

        Logger.info("GoogleOAuth: Redirecting user #{valid_user_id} to Google OAuth")

        redirect(conn, external: auth_url)

      :error ->
        Logger.warning("GoogleOAuth: Invalid UUID format for user_id: #{inspect(user_id)}")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "user_id must be a valid UUID"})
    end
  end

  def authorize(conn, _params) do
    Logger.warning(
      "GoogleOAuth: Missing or invalid user_id query parameter; expected user_id as a UUID"
    )

    conn
    |> put_status(:bad_request)
    |> json(%{error: "user_id query parameter is required and must be a valid UUID"})
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

      {:error, :user_not_found} ->
        Logger.error("GoogleOAuth: User not found for provided user_id")
        redirect(conn, external: frontend_redirect_url("error", "User not found"))

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
         # Use parts: 3 to handle user_ids that might contain colons (future-proofing)
         [user_id, timestamp_str, signature] <- String.split(decoded, ":", parts: 3),
         {timestamp, ""} <- Integer.parse(timestamp_str),
         true <- valid_timestamp?(timestamp),
         true <- valid_signature?(user_id, timestamp_str, signature) do
      {:ok, user_id}
    else
      _ -> {:error, :invalid_state}
    end
  end

  defp valid_timestamp?(timestamp) do
    # State is valid for 10 minutes and cannot be in the future
    current = System.system_time(:second)
    timestamp <= current and current - timestamp < 600
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
        access_token = response["access_token"]
        refresh_token = response["refresh_token"]
        expires_in = response["expires_in"]

        cond do
          is_nil(access_token) or access_token == "" ->
            {:error, :token_exchange_failed,
             "Google did not return an access token during the OAuth exchange."}

          true ->
            # Note: refresh_token may be nil for re-authorization flows.
            # The store_tokens function handles this appropriately.
            {:ok,
             %{
               access_token: access_token,
               refresh_token: refresh_token,
               expires_in: expires_in
             }}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, :token_exchange_failed, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, :token_exchange_failed, reason}
    end
  end

  defp store_tokens(user_id, tokens) do
    # Verify user exists before storing tokens
    case Accounts.get_user(user_id) do
      nil ->
        {:error, :user_not_found}

      _user ->
        do_store_tokens(user_id, tokens)
    end
  end

  defp do_store_tokens(user_id, tokens) do
    expires_at =
      if tokens.expires_in do
        DateTime.add(DateTime.utc_now(), tokens.expires_in, :second)
      else
        nil
      end

    # Check if credential already exists
    case AiCredentials.get_credential_by_user_and_provider(user_id, "gemini") do
      nil ->
        # Create new credential - refresh_token is required for new credentials
        if is_nil(tokens.refresh_token) or tokens.refresh_token == "" do
          {:error,
           "Google did not return a refresh token. Try removing this app's access in your Google Account and reconnecting."}
        else
          AiCredentials.create_credential(%{
            "user_id" => user_id,
            "provider" => "gemini",
            "access_token" => tokens.access_token,
            "refresh_token" => tokens.refresh_token,
            "token_expires_at" => expires_at
          })
        end

      existing ->
        # Update existing credential - preserve old refresh_token if new one is nil
        update_attrs = %{
          "access_token" => tokens.access_token,
          "token_expires_at" => expires_at,
          "status" => "active",
          "status_message" => nil
        }

        update_attrs =
          if tokens.refresh_token do
            Map.put(update_attrs, "refresh_token", tokens.refresh_token)
          else
            update_attrs
          end

        AiCredentials.update_credential(existing, update_attrs)
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
  #
  # OAuth credentials are loaded in this order of precedence:
  # 1. Application config (:shot_elixir, :google_oauth, :client_id/:client_secret)
  # 2. Environment variables (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET)
  #
  # For security, client_id and client_secret should always come from environment
  # variables in production (never committed to source control).
  # The callback_url and frontend_url can be set in config files since they're
  # not sensitive.

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
