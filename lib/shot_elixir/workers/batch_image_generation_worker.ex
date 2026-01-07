defmodule ShotElixir.Workers.BatchImageGenerationWorker do
  @moduledoc """
  Background worker for batch AI image generation.

  This worker handles individual entity image generation operations:
  - Generates a single AI image via Grok API
  - Automatically attaches the image to the entity
  - Tracks progress for batch operations
  - Handles failures gracefully to prevent blocking

  The worker runs in the :images queue with max 3 attempts.
  """

  use Oban.Worker, queue: :images, max_attempts: 3

  alias ShotElixir.Services.{
    AiService,
    GrokService,
    BatchImageGenerationService,
    AiCreditNotificationService
  }

  alias ShotElixir.Characters
  alias ShotElixir.Sites
  alias ShotElixir.Factions
  alias ShotElixir.Parties
  alias ShotElixir.Vehicles
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    entity_type = args["entity_type"]
    entity_id = args["entity_id"]
    campaign_id = args["campaign_id"]
    is_final_attempt = attempt >= max_attempts

    Logger.info(
      "[BatchImageGenerationWorker] Generating image for #{entity_type}:#{entity_id} (attempt #{attempt}/#{max_attempts})"
    )

    try do
      case get_entity(entity_type, entity_id) do
        {:ok, entity} ->
          case generate_and_attach_image(entity_type, entity_id, entity) do
            {:ok, _} ->
              Logger.info(
                "[BatchImageGenerationWorker] Successfully generated image for #{entity_type}:#{entity_id}"
              )

              if campaign_id do
                BatchImageGenerationService.increment_completion(campaign_id)
              end

              :ok

            {:error, :credit_exhausted, message} ->
              Logger.error("[BatchImageGenerationWorker] AI API credits exhausted: #{message}")

              # Notify user about credit exhaustion
              if campaign_id do
                campaign = ShotElixir.Repo.get(ShotElixir.Campaigns.Campaign, campaign_id)

                if campaign do
                  # Use campaign's ai_provider or default to "grok"
                  ai_provider = campaign.ai_provider || "grok"

                  AiCreditNotificationService.handle_credit_exhaustion(
                    campaign_id,
                    campaign.user_id,
                    ai_provider
                  )
                end

                # Increment completion so batch can finish
                BatchImageGenerationService.increment_completion(campaign_id)
              end

              # Discard job - no point retrying when credits are exhausted
              {:discard, :credit_exhausted}

            {:error, reason} ->
              Logger.error(
                "[BatchImageGenerationWorker] Failed to generate image for #{entity_type}:#{entity_id}: #{inspect(reason)} (attempt #{attempt}/#{max_attempts})"
              )

              # On final attempt, increment counter before returning error
              if is_final_attempt && campaign_id do
                Logger.warning(
                  "[BatchImageGenerationWorker] Final attempt failed - incrementing counter to prevent blocking"
                )

                BatchImageGenerationService.increment_completion(campaign_id)
              end

              {:error, reason}
          end

        {:error, :not_found} ->
          Logger.error(
            "[BatchImageGenerationWorker] Entity #{entity_type}:#{entity_id} not found - discarding job"
          )

          # Still increment progress so batch can complete
          if campaign_id do
            BatchImageGenerationService.increment_completion(campaign_id)
          end

          {:discard, :entity_not_found}

        {:error, :unsupported_type} ->
          Logger.error(
            "[BatchImageGenerationWorker] Unsupported entity type #{entity_type} - discarding job"
          )

          # Still increment progress so batch can complete
          if campaign_id do
            BatchImageGenerationService.increment_completion(campaign_id)
          end

          {:discard, :unsupported_type}
      end
    rescue
      e ->
        Logger.error(
          "[BatchImageGenerationWorker] Exception while generating image: #{inspect(e)} (attempt #{attempt}/#{max_attempts})"
        )

        Logger.error(Exception.format(:error, e, __STACKTRACE__))

        if is_final_attempt && campaign_id do
          Logger.warning(
            "[BatchImageGenerationWorker] Final attempt exception - incrementing counter to prevent blocking"
          )

          BatchImageGenerationService.increment_completion(campaign_id)
          {:discard, :exception}
        else
          reraise e, __STACKTRACE__
        end
    end
  end

  # Generate a single image and attach it to the entity
  defp generate_and_attach_image(entity_type, entity_id, entity) do
    with {:ok, prompt} <- build_image_prompt(entity, entity_type),
         {:ok, [image_url | _]} <- GrokService.generate_image(prompt, 1, "url"),
         {:ok, _attachment} <- AiService.attach_image_from_url(entity_type, entity_id, image_url) do
      {:ok, image_url}
    end
  end

  # Build image generation prompt from entity
  defp build_image_prompt(entity, entity_type) do
    prompt =
      cond do
        # Check description field first (for sites, factions, parties)
        Map.has_key?(entity, :description) && is_binary(entity.description) &&
            entity.description != "" ->
          "Generate an image of: #{entity.description}"

        # Check action_values map for characters
        Map.has_key?(entity, :action_values) && is_map(entity.action_values) ->
          build_prompt_from_action_values(entity.action_values, entity.name)

        # Fallback to name
        Map.has_key?(entity, :name) && entity.name ->
          "Generate an image of #{entity.name}"

        # Fallback with entity type for better context
        true ->
          "Generate a #{entity_type} image"
      end

    {:ok, prompt}
  end

  # Build prompt from action_values map (for characters)
  defp build_prompt_from_action_values(action_values, name) do
    background = action_values["Background"] || action_values["background"]
    appearance = action_values["Appearance"] || action_values["appearance"]
    style = action_values["Style of Dress"] || action_values["style"]

    parts =
      [
        if(name, do: "Character named #{name}", else: nil),
        if(appearance && appearance != "", do: "Appearance: #{appearance}", else: nil),
        if(style && style != "", do: "Style: #{style}", else: nil),
        if(background && background != "",
          do: "Background: #{String.slice(background, 0..200)}",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "Generate a character image"
      _ -> "Generate an image of: " <> Enum.join(parts, ". ")
    end
  end

  # Helper to get entity by type and ID
  defp get_entity("Character", id) do
    case Characters.get_character(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp get_entity("Site", id) do
    case Sites.get_site(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp get_entity("Faction", id) do
    case Factions.get_faction(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp get_entity("Party", id) do
    case Parties.get_party(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp get_entity("Vehicle", id) do
    case Vehicles.get_vehicle(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp get_entity(type, _id) do
    Logger.error("[BatchImageGenerationWorker] Unsupported entity type: #{type}")
    {:error, :unsupported_type}
  end
end
