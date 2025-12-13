defmodule ShotElixirWeb.Api.V2.AiImageController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Services.GrokCreditNotificationService

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

              true ->
                # Verify entity exists and belongs to campaign
                case get_entity(entity_class, entity_id, current_user.current_campaign_id) do
                  {:ok, _entity} ->
                    # Start AI image generation in background task
                    campaign_id = campaign.id

                    user_id = current_user.id

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

                        {:error, :credit_exhausted, message} ->
                          # Handle credit exhaustion - notify user
                          GrokCreditNotificationService.handle_credit_exhaustion(
                            campaign_id,
                            user_id
                          )

                          ShotElixirWeb.CampaignChannel.broadcast_ai_image_status(
                            campaign_id,
                            "credit_exhausted",
                            %{error: message}
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
                            image_url =
                              ShotElixir.ActiveStorage.get_image_url(
                                entity_class,
                                refreshed_entity.id
                              )

                            # Return updated entity with image_url
                            serialized_entity =
                              serialize_entity(entity_class, refreshed_entity)
                              |> Map.put(:image_url, image_url)

                            # Broadcast entity update via WebSocket (Rails-compatible format)
                            entity_key = entity_class |> String.downcase() |> String.to_atom()
                            plural_string = pluralize_entity(entity_class)
                            plural_key = String.to_atom(plural_string)

                            IO.puts(
                              "📡 Broadcasting #{entity_class} update to campaign:#{current_user.current_campaign_id}"
                            )

                            IO.puts(
                              "🔑 Entity key: #{inspect(entity_key)}, Plural key: #{inspect(plural_key)} (from '#{plural_string}')"
                            )

                            IO.inspect(serialized_entity, label: "#{entity_class} data")

                            # Use Phoenix PubSub for campaign broadcast with plural reload signal
                            Phoenix.PubSub.broadcast!(
                              ShotElixir.PubSub,
                              "campaign:#{current_user.current_campaign_id}",
                              {:campaign_broadcast,
                               %{entity_key => serialized_entity, plural_key => "reload"}}
                            )

                            IO.puts("✅ Broadcast sent successfully")

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
    import Ecto.Query

    query =
      from c in ShotElixir.Characters.Character,
        where: c.id == ^entity_id and c.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      character -> {:ok, character}
    end
  end

  defp get_entity("Vehicle", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from v in ShotElixir.Vehicles.Vehicle,
        where: v.id == ^entity_id and v.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      vehicle -> {:ok, vehicle}
    end
  end

  defp get_entity("Party", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from p in ShotElixir.Parties.Party,
        where: p.id == ^entity_id and p.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      party -> {:ok, party}
    end
  end

  defp get_entity("Faction", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from f in ShotElixir.Factions.Faction,
        where: f.id == ^entity_id and f.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      faction -> {:ok, faction}
    end
  end

  defp get_entity("Site", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from s in ShotElixir.Sites.Site,
        where: s.id == ^entity_id and s.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      site -> {:ok, site}
    end
  end

  defp get_entity("Weapon", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from w in ShotElixir.Weapons.Weapon,
        where: w.id == ^entity_id and w.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      weapon -> {:ok, weapon}
    end
  end

  defp get_entity("Schtick", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from s in ShotElixir.Schticks.Schtick,
        where: s.id == ^entity_id and s.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      schtick -> {:ok, schtick}
    end
  end

  defp get_entity("Fight", entity_id, campaign_id) do
    import Ecto.Query

    query =
      from f in ShotElixir.Fights.Fight,
        where: f.id == ^entity_id and f.campaign_id == ^campaign_id

    case ShotElixir.Repo.one(query) do
      nil -> {:error, :not_found}
      fight -> {:ok, fight}
    end
  end

  defp get_entity(_, _, _), do: {:error, :not_found}

  # Pluralize entity class names for Rails-compatible broadcast keys
  defp pluralize_entity("Party"), do: "parties"
  defp pluralize_entity(entity_class), do: String.downcase(entity_class) <> "s"

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
      entity_class: "Character",
      active: character.active,
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
      entity_class: "Vehicle",
      active: vehicle.active,
      name: vehicle.name,
      vehicle_type: vehicle.vehicle_type,
      description: vehicle.description,
      campaign_id: vehicle.campaign_id,
      created_at: vehicle.created_at,
      updated_at: vehicle.updated_at
    }
  end

  defp serialize_entity("Party", party) do
    %{
      id: party.id,
      entity_class: "Party",
      active: party.active,
      name: party.name,
      description: party.description,
      campaign_id: party.campaign_id,
      created_at: party.created_at,
      updated_at: party.updated_at
    }
  end

  defp serialize_entity("Faction", faction) do
    %{
      id: faction.id,
      entity_class: "Faction",
      active: faction.active,
      name: faction.name,
      description: faction.description,
      campaign_id: faction.campaign_id,
      created_at: faction.created_at,
      updated_at: faction.updated_at
    }
  end

  defp serialize_entity("Site", site) do
    %{
      id: site.id,
      entity_class: "Site",
      active: site.active,
      name: site.name,
      description: site.description,
      campaign_id: site.campaign_id,
      created_at: site.created_at,
      updated_at: site.updated_at
    }
  end

  defp serialize_entity("Weapon", weapon) do
    %{
      id: weapon.id,
      entity_class: "Weapon",
      active: weapon.active,
      name: weapon.name,
      description: weapon.description,
      campaign_id: weapon.campaign_id,
      created_at: weapon.created_at,
      updated_at: weapon.updated_at
    }
  end

  defp serialize_entity("Schtick", schtick) do
    %{
      id: schtick.id,
      entity_class: "Schtick",
      active: schtick.active,
      name: schtick.name,
      description: schtick.description,
      campaign_id: schtick.campaign_id,
      created_at: schtick.created_at,
      updated_at: schtick.updated_at
    }
  end

  defp serialize_entity("Fight", fight) do
    %{
      id: fight.id,
      entity_class: "Fight",
      active: fight.active,
      name: fight.name,
      description: fight.description,
      campaign_id: fight.campaign_id,
      created_at: fight.created_at,
      updated_at: fight.updated_at
    }
  end

  defp serialize_entity(_, entity), do: entity
end
