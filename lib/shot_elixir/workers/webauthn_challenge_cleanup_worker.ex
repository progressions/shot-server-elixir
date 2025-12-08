defmodule ShotElixir.Workers.WebauthnChallengeCleanupWorker do
  @moduledoc """
  Background worker for cleaning up expired WebAuthn challenges.

  Runs periodically to remove challenges that are:
  - Already used
  - Expired (past their expires_at timestamp)
  - Older than 24 hours (stale)

  This prevents database bloat from accumulating challenge records.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ShotElixir.Repo
  alias ShotElixir.Accounts.WebauthnChallenge
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting WebAuthn challenge cleanup")

    # Delete challenges that are:
    # 1. Already used
    # 2. Expired (past expires_at)
    # 3. Older than 24 hours (stale, regardless of status)
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    now = DateTime.utc_now()

    {deleted_count, _} =
      from(c in WebauthnChallenge,
        where:
          c.used == true or
            c.expires_at < ^now or
            c.inserted_at < ^cutoff
      )
      |> Repo.delete_all()

    Logger.info("WebAuthn challenge cleanup completed: #{deleted_count} challenges deleted")

    :ok
  end
end
