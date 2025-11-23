defmodule ShotElixir.Workers.AiCharacterCreationWorker do
  @moduledoc """
  Background worker for AI character creation via Oban.

  Generates a new character using AI based on a description and broadcasts
  the result to the campaign channel for preview.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ShotElixir.Services.AiService
  alias ShotElixirWeb.CampaignChannel
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"description" => description, "campaign_id" => campaign_id}}) do
    Logger.info("Starting AI character creation for campaign #{campaign_id}")

    case AiService.generate_character(description, campaign_id) do
      {:ok, json} ->
        Logger.info("Generated AI character JSON: #{inspect(json)}")

        # Broadcast preview to campaign channel
        CampaignChannel.broadcast_ai_image_status(campaign_id, "preview_ready", %{json: json})

        :ok

      {:error, %{"error" => error}} ->
        Logger.error("AI service returned error: #{error}")
        CampaignChannel.broadcast_ai_image_status(campaign_id, "error", %{error: error})
        {:error, error}

      {:error, reason} ->
        Logger.error("AI character creation failed: #{inspect(reason)}")

        error_message =
          if is_binary(reason), do: reason, else: "Character generation failed"

        CampaignChannel.broadcast_ai_image_status(campaign_id, "error", %{error: error_message})

        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in AI character creation: #{inspect(e)}")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))

      error_message = Exception.message(e)
      CampaignChannel.broadcast_ai_image_status(campaign_id, "error", %{error: error_message})

      reraise e, __STACKTRACE__
  end
end
