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
            # Extract AI image parameters (handle both nested and flat formats)
            ai_image_params = params["ai_image"] || params
            entity_class = ai_image_params["entity_class"]
            entity_id = ai_image_params["entity_id"]

            # Validate required parameters
            cond do
              is_nil(entity_class) || String.trim(entity_class) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_class parameter is required"})

              is_nil(entity_id) || String.trim(entity_id) == "" ->
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
                    # Start AI image generation in background task
                    campaign_id = campaign.id

                    Task.start(fn ->
                      case ShotElixir.Services.AiService.generate_images_for_entity(
                             entity_class,
                             entity_id,
                             3
                           ) do
                        {:ok, urls} when is_list(urls) ->
                          # Broadcast success with image URLs as JSON
                          json = Jason.encode!(urls)

                          ShotElixirWeb.CampaignChannel.broadcast_ai_image_status(
                            campaign_id,
                            "preview_ready",
                            %{json: json}
                          )

                        {:error, reason} ->
                          # Broadcast error
                          error_message = "Failed to generate images: #{inspect(reason)}"

                          ShotElixirWeb.CampaignChannel.broadcast_ai_image_status(
                            campaign_id,
                            "error",
                            %{error: error_message}
                          )
                      end
                    end)

                    # Return immediate response like Rails
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
    IO.inspect(params, label: "AI Image attach params")
    current_user = Guardian.Plug.current_resource(conn)
    IO.inspect({current_user.id, current_user.current_campaign_id}, label: "User and Campaign")

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_modification(campaign, current_user) do
            # Extract AI image parameters (handle both nested and flat formats)
            ai_image_params = params["ai_image"] || params
            entity_class = ai_image_params["entity_class"]
            entity_id = ai_image_params["entity_id"]
            image_url = ai_image_params["image_url"]

            # Validate required parameters
            cond do
              is_nil(entity_class) || String.trim(entity_class) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_class parameter is required"})

              is_nil(entity_id) || String.trim(entity_id) == "" ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "entity_id parameter is required"})

              is_nil(image_url) || String.trim(image_url) == "" ->
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
                    # Attach image from URL using AI service
                    case ShotElixir.Services.AiService.attach_image_from_url(
                           entity_class,
                           entity.id,
                           image_url
                         ) do
                      {:ok, _attachment} ->
                        # Reload entity to get fresh data
                        case get_entity(entity_class, entity_id, current_user.current_campaign_id) do
                          {:ok, refreshed_entity} ->
                            # Get updated image URL
                            image_url = ShotElixir.ActiveStorage.get_image_url(entity_class, refreshed_entity.id)

                            # Return updated entity with image_url
                            serialized_entity =
                              serialize_entity(entity_class, refreshed_entity)
                              |> Map.put(:image_url, image_url)

                            # Broadcast character update via WebSocket (Rails-compatible format)
                            if entity_class == "Character" do
                              IO.puts("📡 Broadcasting character update to campaign:#{current_user.current_campaign_id}")
                              IO.inspect(serialized_entity, label: "Character data")

                              # Use Phoenix PubSub for Rails-compatible broadcast
                              Phoenix.PubSub.broadcast!(
                                ShotElixir.PubSub,
                                "campaign:#{current_user.current_campaign_id}",
                                {:rails_message, %{character: serialized_entity}}
                              )

                              IO.puts("✅ Broadcast sent successfully")
                            end

                            conn
                            |> put_status(:ok)
                            |> json(%{
                              entity: serialized_entity,
                              serializer: "#{entity_class}Serializer"
                            })

                          {:error, _} ->
                            # Fallback to original entity if reload fails
                            serialized_entity =
                              serialize_entity(entity_class, entity)
                              |> Map.put(
                                :image_url,
                                ShotElixir.ActiveStorage.get_image_url(entity_class, entity.id)
                              )

                            conn
                            |> put_status(:ok)
                            |> json(%{
                              entity: serialized_entity,
                              serializer: "#{entity_class}Serializer"
                            })
                        end

                      {:error, reason} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> json(%{error: "Failed to attach image: #{inspect(reason)}"})
                    end

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
    # Extract archetype from action_values map if it exists
    archetype =
      if is_map(character.action_values) do
        character.action_values["Archetype"]
      else
        nil
      end

    %{
      id: character.id,
      name: character.name,
      archetype: archetype,
      action_values: character.action_values,
      description: character.description,
      skills: character.skills,
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
