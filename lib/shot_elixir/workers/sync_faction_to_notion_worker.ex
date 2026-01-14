defmodule ShotElixir.Workers.SyncFactionToNotionWorker do
  @moduledoc """
  Background worker for syncing factions to Notion.
  Only runs in production environment.
  """

  use Oban.Worker,
    queue: :notion,
    max_attempts: 3,
    unique: [period: 60, fields: [:args], states: [:available, :scheduled, :executing, :retryable]]

  alias ShotElixir.Factions
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"faction_id" => faction_id}}) do
    # Only run in production to avoid unwanted API calls in test/dev
    if Application.get_env(:shot_elixir, :environment) == :prod do
      faction = Factions.get_faction!(faction_id)

      case NotionService.sync_faction(faction) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
