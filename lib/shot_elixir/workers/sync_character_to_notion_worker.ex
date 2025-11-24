defmodule ShotElixir.Workers.SyncCharacterToNotionWorker do
  @moduledoc """
  Background worker for syncing characters to Notion.
  Only runs in production environment.
  """

  use Oban.Worker, queue: :notion, max_attempts: 3

  alias ShotElixir.Characters
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"character_id" => character_id}}) do
    # Only run in production
    if Application.get_env(:shot_elixir, :env) == :prod do
      character = Characters.get_character!(character_id)
      NotionService.sync_character(character)
    end

    :ok
  end
end
