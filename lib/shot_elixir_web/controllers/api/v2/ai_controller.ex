defmodule ShotElixirWeb.Api.V2.AiController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # POST /api/v2/ai
  # Starts AI character creation job with description parameter
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            # Extract AI parameters
            ai_params = params["ai"] || %{}
            description = ai_params["description"]

            if description && String.trim(description) != "" do
              # TODO: Start AI character creation job
              # AiCharacterCreationJob.perform_later(description, campaign.id)

              # For now, return immediate response like Rails
              conn
              |> put_status(:accepted)
              |> json(%{message: "Character generation in progress"})
            else
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Description parameter is required"})
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # PATCH/PUT /api/v2/ai/:id/extend
  # Updates an existing character with AI
  def extend(conn, %{"id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            # Find character in current campaign
            case Characters.get_character(character_id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Character not found"})

              character ->
                if character.campaign_id == current_user.current_campaign_id do
                  # TODO: Start AI character update job
                  # AiCharacterUpdateJob.perform_later(character.id)

                  # For now, return success response
                  conn
                  |> put_status(:accepted)
                  |> json(%{message: "Character AI update in progress"})
                else
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Character not found"})
                end
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # Private helper functions
  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id || user.admin ||
    (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
    Campaigns.is_member?(campaign.id, user.id)
  end
end
