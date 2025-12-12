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

        # Try to get campaign_id for error broadcast and clear extending flag
        case get_character(character_id) do
          {:ok, character} ->
            # Clear extending flag on error (safe - won't crash if update fails)
            safe_clear_extending_flag(character)

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

      # Try to clear extending flag and broadcast error
      case get_character(character_id) do
        {:ok, character} ->
          # Clear extending flag on exception (safe - won't crash if update fails)
          safe_clear_extending_flag(character)

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

  # Safely clear the extending flag without crashing on errors.
  # Used in error/exception handlers where we must not fail the cleanup.
  defp safe_clear_extending_flag(character) do
    case Characters.update_character(character, %{extending: false}) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to clear extending flag for character #{character.id}: #{inspect(changeset.errors)}"
        )

        :error
    end
  end

  defp update_character(character, json) do
    Logger.info("Generated AI character JSON: #{inspect(json)}")
    Logger.info("Original character description: #{inspect(character.description)}")

    # Merge AI-generated data with existing character
    updated_character = AiService.merge_json_with_character(json, character)

    Logger.info("Merged character description: #{inspect(updated_character.description)}")

    # Save to database, also clearing the extending flag.
    #
    # IMPORTANT: Pass the original `character` (not updated_character) so the changeset
    # can detect the difference between the original DB values and the new merged values.
    #
    # WHY: Ecto.Changeset.change/2 compares the incoming attributes against the struct's
    # current field values to determine what has changed. If you pass a struct that already
    # has the merged/updated values (like `updated_character`), Ecto will see no difference
    # and will not persist any changes. Always pass the original struct from the DB so Ecto
    # can properly detect and save the updates.
    case Characters.update_character(character, %{
           description: updated_character.description,
           wealth: updated_character.wealth,
           extending: false
         }) do
      {:ok, saved_character} ->
        {:ok, saved_character}

      {:error, changeset} ->
        Logger.error("Failed to save character: #{inspect(changeset.errors)}")
        {:error, "Failed to save character updates"}
    end
  end

  defp broadcast_character_update(character) do
    # Note: This broadcasts AI completion status, not a duplicate of the
    # normal character update broadcast from Characters.update_character.
    # The frontend listens for {status: "character_ready"} to know AI processing is done.

    # Preload campaign and all associations required for rendering
    character_with_assocs =
      Repo.preload(character, [
        :campaign,
        :user,
        :faction,
        :juncture,
        :image_positions,
        :schticks,
        :weapons,
        :parties,
        :sites,
        :advancements
      ])

    # Get serialized character data
    character_data =
      ShotElixirWeb.Api.V2.CharacterView.render("show.json", %{character: character_with_assocs})

    # Broadcast to campaign channel
    CampaignChannel.broadcast_ai_image_status(
      character_with_assocs.campaign_id,
      "character_ready",
      %{
        character: character_data
      }
    )
  end
end
