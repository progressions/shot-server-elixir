defmodule ShotElixir.Workers.CliAuthCodeCleanupWorker do
  @moduledoc """
  Background worker for cleaning up expired CLI authorization codes.

  Runs periodically to remove codes that are:
  - Expired (past their expires_at timestamp)
  - Older than 24 hours (stale, regardless of status)

  This prevents database bloat from accumulating authorization code records.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ShotElixir.Repo
  alias ShotElixir.Accounts.CliAuthorizationCode
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting CLI authorization code cleanup")

    # Delete codes that are:
    # 1. Expired (past expires_at)
    # 2. Older than 24 hours (stale, regardless of status)
    cutoff = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    now = DateTime.utc_now()

    {deleted_count, _} =
      from(c in CliAuthorizationCode,
        where: c.expires_at < ^now or c.inserted_at < ^cutoff
      )
      |> Repo.delete_all()

    Logger.info("CLI authorization code cleanup completed: #{deleted_count} codes deleted")

    :ok
  end
end
