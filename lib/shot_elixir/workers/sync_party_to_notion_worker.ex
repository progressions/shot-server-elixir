defmodule ShotElixir.Workers.SyncPartyToNotionWorker do
  @moduledoc """
  Background worker for syncing parties to Notion.
  Only runs in production environment.
  """

  use Oban.Worker, queue: :notion, max_attempts: 3

  alias ShotElixir.Parties
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"party_id" => party_id}}) do
    # Only run in production to avoid unwanted API calls in test/dev
    if Application.get_env(:shot_elixir, :environment) == :prod do
      party = Parties.get_party!(party_id)

      case NotionService.sync_party(party) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
