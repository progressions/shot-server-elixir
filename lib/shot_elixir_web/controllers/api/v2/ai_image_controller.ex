defmodule ShotElixirWeb.Api.V2.AiImageController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Vehicles
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # POST /api/v2/ai_images
  # Queues background job for AI image generation
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
            # Extract AI image parameters
            ai_image_params = params["ai_image"] || %{}
            entity_class = ai_image_params["entity_class"]
            entity_id = ai_image_params["entity_id"]

            # Validate required parameters
            cond do
              not entity_class || String.trim(entity_class) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_class parameter is required"})

              not entity_id || String.trim(entity_id) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_id parameter is required"})

              entity_class not in ["Character", "Vehicle"] ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_class must be Character or Vehicle"})

              true ->
                # Verify entity exists and belongs to campaign
                case get_entity(entity_class, entity_id, current_user.current_campaign_id) do
                  {:ok, _entity} ->
                    # TODO: Start AI image creation job
                    # AiImageCreationJob.perform_later(entity_class, entity_id, campaign.id)

                    # For now, return immediate response like Rails
                    conn
                    |> put_status(:accepted)
                    |> json(%{message: "Character generation in progress"})

                  {:error, :not_found} ->
                    conn
                    |> put_status(:not_found)
                    |> json(%{error: "#{entity_class} not found"})

                  {:error, :wrong_campaign} ->
                    conn
                    |> put_status(:not_found)
                    |> json(%{error: "#{entity_class} not found"})
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

  # POST /api/v2/ai_images/attach
  # Attaches image from URL to an entity
  def attach(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_modification(campaign, current_user) do
            # Extract AI image parameters
            ai_image_params = params["ai_image"] || %{}
            entity_class = ai_image_params["entity_class"]
            entity_id = ai_image_params["entity_id"]
            image_url = ai_image_params["image_url"]

            # Validate required parameters
            cond do
              not entity_class || String.trim(entity_class) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_class parameter is required"})

              not entity_id || String.trim(entity_id) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_id parameter is required"})

              not image_url || String.trim(image_url) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "image_url parameter is required"})

              entity_class not in ["Character", "Vehicle"] ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_class must be Character or Vehicle"})

              true ->
                # Verify entity exists and belongs to campaign
                case get_entity(entity_class, entity_id, current_user.current_campaign_id) do
                  {:ok, entity} ->
                    # TODO: Implement AI service to attach image from URL
                    # updated_entity = AiService.attach_image_from_url(entity, image_url)

                    # For now, return the entity as-is
                    serialized_entity = serialize_entity(entity_class, entity)

                    conn
                    |> put_status(:ok)
                    |> json(%{
                      entity: serialized_entity,
                      serializer: "#{entity_class}Serializer"
                    })

                  {:error, :not_found} ->
                    conn
                    |> put_status(:not_found)
                    |> json(%{error: "#{entity_class} not found"})

                  {:error, :wrong_campaign} ->
                    conn
                    |> put_status(:not_found)
                    |> json(%{error: "#{entity_class} not found"})
                end
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only gamemaster can attach images"})
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

  defp authorize_campaign_modification(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id))
  end

  defp get_entity("Character", entity_id, campaign_id) do
    case Characters.get_character(entity_id) do
      nil ->
        {:error, :not_found}

      character ->
        if character.campaign_id == campaign_id do
          {:ok, character}
        else
          {:error, :wrong_campaign}
        end
    end
  end

  defp get_entity("Vehicle", entity_id, campaign_id) do
    case Vehicles.get_vehicle(entity_id) do
      nil ->
        {:error, :not_found}

      vehicle ->
        if vehicle.campaign_id == campaign_id do
          {:ok, vehicle}
        else
          {:error, :wrong_campaign}
        end
    end
  end

  defp get_entity(_, _, _), do: {:error, :not_found}

  defp serialize_entity("Character", character) do
    %{
      id: character.id,
      name: character.name,
      archetype: character.archetype,
      description: character.description,
      campaign_id: character.campaign_id,
      created_at: character.created_at,
      updated_at: character.updated_at
    }
  end

  defp serialize_entity("Vehicle", vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      vehicle_type: vehicle.vehicle_type,
      description: vehicle.description,
      campaign_id: vehicle.campaign_id,
      created_at: vehicle.created_at,
      updated_at: vehicle.updated_at
    }
  end

  defp serialize_entity(_, entity), do: entity
end
