defmodule ShotElixir.Workers.SyncSiteToNotionWorker do
  @moduledoc """
  Background worker for syncing sites to Notion.
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

  alias ShotElixir.Sites
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_id" => site_id}}) do
    # Only run in production to avoid unwanted API calls in test/dev
    if Application.get_env(:shot_elixir, :environment) == :prod do
      site = Sites.get_site!(site_id)

      case NotionService.sync_site(site) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
