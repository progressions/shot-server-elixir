defmodule ShotElixir.Guardian do
  use Guardian, otp_app: :shot_elixir
  require Logger

  alias ShotElixir.Accounts

  def subject_for_token(user, _claims) do
    {:ok, to_string(user.id)}
  end

  # Handle Rails JWT format with nested user data
  def resource_from_claims(%{"jti" => _jti, "user" => user_data} = claims)
      when is_map(user_data) do
    Logger.info("[Guardian] Processing Rails JWT format")
    IO.inspect(claims, label: "Rails JWT claims")
    # Rails JWT contains user email in nested user map
    email = user_data["email"] || user_data[:email]
    IO.inspect(email, label: "Looking for email")

    case Accounts.get_user_by_email(email) do
      nil ->
        Logger.warning("[Guardian] User not found for email: #{email}")
        {:error, :user_not_found}

      user ->
        Logger.info("[Guardian] Found user: #{user.email}")
        # For Rails compatibility, we trust the JTI from the token
        {:ok, user}
    end
  end

  # Handle Elixir-generated tokens with sub field
  def resource_from_claims(%{"sub" => id, "jti" => jti}) do
    Logger.info(
      "[Guardian] Processing Elixir token - sub: #{id}, jti: #{String.slice(jti || "", 0, 8)}..."
    )

    case Accounts.get_user(id) do
      nil ->
        Logger.warning("[Guardian] User not found for id: #{id}")
        {:error, :user_not_found}

      user ->
        Logger.info(
          "[Guardian] Found user: #{user.email}, DB jti: #{String.slice(user.jti || "", 0, 8)}..."
        )

        # Verify JTI matches for revocation support
        if user.jti == jti do
          Logger.info("[Guardian] JTI match - authentication successful")
          {:ok, user}
        else
          Logger.warning("[Guardian] JTI MISMATCH - token jti: #{jti}, db jti: #{user.jti}")
          {:error, :token_revoked}
        end
    end
  end

  def resource_from_claims(claims) do
    Logger.warning("[Guardian] Invalid claims structure: #{inspect(claims)}")
    {:error, :invalid_claims}
  end

  def build_claims(claims, user, _opts) do
    claims =
      claims
      |> Map.put("jti", user.jti)
      |> Map.put("user", %{
        id: user.id,
        email: user.email,
        admin: user.admin,
        first_name: user.first_name,
        last_name: user.last_name,
        gamemaster: user.gamemaster,
        current_campaign: user.current_campaign_id,
        created_at: user.created_at,
        updated_at: user.updated_at
      })

    {:ok, claims}
  end
end
