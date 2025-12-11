defmodule ShotElixir.Workers.LinkCodeCleanupWorker do
  @moduledoc """
  Background worker for cleaning up expired Discord link codes.

  Runs periodically to remove expired codes from the LinkCodes Agent,
  preventing memory accumulation from stale codes.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ShotElixir.Discord.LinkCodes
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting Discord link code cleanup")

    LinkCodes.cleanup_expired()

    Logger.info("Discord link code cleanup completed")

    :ok
  end
end
