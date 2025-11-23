defmodule ShotElixir.Workers.AiCharacterUpdateWorker do
  @moduledoc """
  Background worker for AI character extension via Oban.

  Extends an existing character with AI-generated details and updates the database.
  Broadcasts the updated character to the campaign channel.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ShotElixir.Services.AiService
  alias ShotElixir.Characters
  alias ShotElixir.Repo
  alias ShotElixirWeb.CampaignChannel
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"character_id" => character_id}}) do
    Logger.info("Starting AI character extension for character #{character_id}")

    with {:ok, character} <- get_character(character_id),
         {:ok, json} <- AiService.extend_character(character_id),
         {:ok, updated_character} <- update_character(character, json) do
      Logger.info("Successfully extended character #{character_id}")

      # Broadcast updated character to campaign channel
      broadcast_character_update(updated_character)

      :ok
    else
      {:error, reason} ->
        Logger.error("AI character extension failed: #{inspect(reason)}")

        # Try to get campaign_id for error broadcast
        case get_character(character_id) do
          {:ok, character} ->
            error_message =
              if is_binary(reason), do: reason, else: "Character extension failed"

            CampaignChannel.broadcast_ai_image_status(character.campaign_id, "error", %{
              error: error_message
            })

          _ ->
            :ok
        end

        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in AI character extension: #{inspect(e)}")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))

      # Try to broadcast error
      case get_character(character_id) do
        {:ok, character} ->
          CampaignChannel.broadcast_ai_image_status(character.campaign_id, "error", %{
            error: Exception.message(e)
          })

        _ ->
          :ok
      end

      reraise e, __STACKTRACE__
  end

  # Private functions

  defp get_character(character_id) do
    case Characters.get_character(character_id) do
      nil -> {:error, "Character not found"}
      character -> {:ok, character}
    end
  end

  defp update_character(character, json) do
    Logger.info("Generated AI character JSON: #{inspect(json)}")

    # Merge AI-generated data with existing character
    updated_character = AiService.merge_json_with_character(json, character)

    # Save to database
    case Characters.update_character(updated_character, %{
           description: updated_character.description,
           wealth: updated_character.wealth
         }) do
      {:ok, saved_character} ->
        {:ok, saved_character}

      {:error, changeset} ->
        Logger.error("Failed to save character: #{inspect(changeset.errors)}")
        {:error, "Failed to save character updates"}
    end
  end

  defp broadcast_character_update(character) do
    # Preload campaign to get campaign_id
    character_with_campaign = Repo.preload(character, :campaign)

    # Get serialized character data
    character_data =
      ShotElixirWeb.Api.V2.CharacterView.render("show.json", %{character: character})

    # Broadcast to campaign channel
    CampaignChannel.broadcast_ai_image_status(
      character_with_campaign.campaign_id,
      "character_ready",
      %{
        character: character_data
      }
    )
  end
end
