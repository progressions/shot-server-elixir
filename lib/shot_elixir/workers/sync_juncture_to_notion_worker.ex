defmodule ShotElixir.Workers.SyncJunctureToNotionWorker do
  @moduledoc """
  Background worker for syncing junctures to Notion.
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

  alias ShotElixir.Junctures
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"juncture_id" => juncture_id}}) do
    # Only run in production to avoid unwanted API calls in test/dev
    if Application.get_env(:shot_elixir, :environment) == :prod do
      juncture = Junctures.get_juncture!(juncture_id)

      case NotionService.sync_juncture(juncture) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
