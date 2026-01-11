defmodule ShotElixir.Workers.SyncCharactersFromNotionWorker do
  @moduledoc """
  Periodic background worker that syncs all Notion-linked characters FROM Notion.

  This worker runs on a configurable schedule (default: every 6 hours) and updates
  all characters that have a linked Notion page with the latest data from Notion.

  Configuration:
    config :shot_elixir, :notion,
      periodic_sync_enabled: true,
      periodic_sync_interval_hours: 6

  Only runs in production environment to avoid unwanted API calls in test/dev.
  """

  use Oban.Worker, queue: :notion, max_attempts: 1

  require Logger

  alias ShotElixir.Characters.Character
  alias ShotElixir.Services.NotionService
  alias ShotElixir.Repo

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if should_run?() do
      sync_all_linked_characters()
    else
      Logger.debug("Periodic Notion sync skipped (not in production or disabled)")
      :ok
    end
  end

  @doc """
  Syncs all characters that have a linked Notion page.
  Returns {:ok, summary} with counts of synced/failed/skipped characters.
  """
  def sync_all_linked_characters do
    characters = get_notion_linked_characters()
    total = length(characters)

    Logger.info("Starting periodic Notion sync for #{total} characters")

    results =
      Enum.map(characters, fn character ->
        sync_character(character)
      end)

    success_count = Enum.count(results, fn {status, _} -> status == :ok end)
    error_count = Enum.count(results, fn {status, _} -> status == :error end)

    Logger.info(
      "Periodic Notion sync completed: #{success_count} synced, #{error_count} failed, #{total} total"
    )

    {:ok, %{total: total, success: success_count, errors: error_count}}
  end

  @doc """
  Returns all characters that have a notion_page_id set.
  """
  def get_notion_linked_characters do
    query =
      from c in Character,
        where: not is_nil(c.notion_page_id) and c.active == true,
        order_by: [asc: c.updated_at]

    Repo.all(query)
  end

  # Sync a single character from Notion
  defp sync_character(character) do
    case NotionService.update_character_from_notion(character) do
      {:ok, updated_character} ->
        Logger.debug("Synced character #{character.id} (#{character.name}) from Notion")
        {:ok, updated_character}

      {:error, reason} ->
        Logger.warning(
          "Failed to sync character #{character.id} (#{character.name}) from Notion: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    error ->
      Logger.error(
        "Exception syncing character #{character.id} from Notion: #{Exception.message(error)}"
      )

      {:error, error}
  end

  # Check if we should run the sync
  defp should_run? do
    Application.get_env(:shot_elixir, :environment) == :prod and
      periodic_sync_enabled?()
  end

  defp periodic_sync_enabled? do
    Application.get_env(:shot_elixir, :notion)[:periodic_sync_enabled] != false
  end
end
