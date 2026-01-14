defmodule ShotElixir.Workers.SyncCharacterToNotionWorker do
  @moduledoc """
  Background worker for syncing characters to Notion.
  Only runs in production environment.
  """

  use Oban.Worker,
    queue: :notion,
    max_attempts: 3,
    unique: [
      period: 60,
      fields: [:args],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias ShotElixir.Characters
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"character_id" => character_id}}) do
    # Only run in production to avoid unwanted API calls in test/dev
    if Application.get_env(:shot_elixir, :environment) == :prod do
      character = Characters.get_character!(character_id)

      case NotionService.sync_character(character) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
