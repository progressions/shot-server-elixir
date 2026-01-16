defmodule ShotElixir.Workers.SyncAdventureToNotionWorker do
  @moduledoc """
  Background worker for syncing adventures to Notion.
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

  alias ShotElixir.Adventures
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"adventure_id" => adventure_id}}) do
    # Only run in production to avoid unwanted API calls in test/dev
    if Application.get_env(:shot_elixir, :environment) == :prod do
      adventure = Adventures.get_adventure!(adventure_id)

      case NotionService.sync_adventure(adventure) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
