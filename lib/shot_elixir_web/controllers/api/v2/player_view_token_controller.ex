defmodule ShotElixirWeb.Api.V2.PlayerViewTokenController do
  @moduledoc """
  Controller for generating and redeeming magic link tokens for Player View access.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Encounters
  alias ShotElixir.Fights
  alias ShotElixir.Characters
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixirWeb.AuthHelpers

  action_fallback ShotElixirWeb.FallbackController

  @frontend_url Application.compile_env(:shot_elixir, :frontend_url, "https://chiwar.net")

  # GET /api/v2/encounters/:encounter_id/player_tokens
  # Lists valid (unexpired, unused) tokens for the encounter
  # Requires authentication and GM access
  def index(conn, %{"encounter_id" => encounter_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight_with_access(encounter_id, current_user),
         {:ok, _campaign} <- get_campaign_with_gm_access(fight.campaign_id, current_user) do
      tokens = Encounters.list_valid_tokens_for_fight(fight.id)

      conn
      |> put_view(ShotElixirWeb.Api.V2.PlayerViewTokenView)
      |> render("index.json", tokens: tokens, frontend_url: frontend_url())
    else
      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{error: message})
    end
  end

  # POST /api/v2/encounters/:encounter_id/player_tokens
  # Creates a magic link token for a character in the encounter
  # Requires authentication and GM access
  def create(conn, %{"encounter_id" => encounter_id, "character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight_with_access(encounter_id, current_user),
         {:ok, _campaign} <- get_campaign_with_gm_access(fight.campaign_id, current_user),
         {:ok, character} <- get_character_in_fight(fight.id, character_id) do
      case Encounters.create_player_view_token(fight, character) do
        {:ok, token} ->
          conn
          |> put_status(:created)
          |> put_view(ShotElixirWeb.Api.V2.PlayerViewTokenView)
          |> render("show.json", token: token, frontend_url: frontend_url())

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to create token", details: changeset_errors(changeset)})
      end
    else
      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{error: message})
    end
  end

  # POST /api/v2/player_tokens/:token/redeem
  # Redeems a magic link token and returns JWT for authentication
  # This is a PUBLIC endpoint (no authentication required)
  def redeem(conn, %{"token" => token_string}) do
    case Encounters.redeem_token(token_string) do
      {:ok, token} ->
        # Generate auth response for the user
        {jwt, user_json} = AuthHelpers.generate_auth_response(token.user)

        # Build redirect URL for Player View
        redirect_url = "#{frontend_url()}/encounters/#{token.fight_id}/play/#{token.character_id}"

        conn
        |> put_status(:ok)
        |> put_view(ShotElixirWeb.Api.V2.PlayerViewTokenView)
        |> render("redeem.json",
          jwt: jwt,
          user: user_json,
          encounter_id: token.fight_id,
          character_id: token.character_id,
          redirect_url: redirect_url
        )

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "Token has expired"})

      {:error, :already_used} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "Token has already been used"})
    end
  end

  # Private helpers

  defp get_fight_with_access(fight_id, user) do
    case Fights.get_fight(fight_id) do
      nil ->
        {:error, :not_found, "Encounter not found"}

      fight ->
        # Verify user has access to this campaign
        if fight.campaign_id == user.current_campaign_id do
          {:ok, fight}
        else
          {:error, :forbidden, "Access denied"}
        end
    end
  end

  defp get_campaign_with_gm_access(campaign_id, user) do
    case Campaigns.get_campaign(campaign_id) do
      nil ->
        {:error, :not_found, "Campaign not found"}

      campaign ->
        if campaign.user_id == user.id || (user.gamemaster && is_member?(campaign_id, user.id)) do
          {:ok, campaign}
        else
          {:error, :forbidden, "Only gamemasters can generate player view links"}
        end
    end
  end

  defp get_character_in_fight(fight_id, character_id) do
    case Characters.get_character(character_id) do
      nil ->
        {:error, :not_found, "Character not found"}

      character ->
        if Encounters.character_in_fight?(fight_id, character_id) do
          {:ok, character}
        else
          {:error, :unprocessable_entity, "Character is not in this encounter"}
        end
    end
  end

  defp is_member?(campaign_id, user_id) do
    Campaigns.is_member?(campaign_id, user_id)
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp frontend_url do
    Application.get_env(:shot_elixir, :frontend_url, @frontend_url)
  end
end
