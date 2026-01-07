defmodule ShotElixir.Notion do
  @moduledoc """
  The Notion context - handles Notion sync logging and related operations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Notion.NotionSyncLog
  alias ShotElixir.Characters

  @doc """
  Creates a sync log entry.

  ## Parameters
    - attrs: Map with :character_id, :status, :payload, :response, :error_message

  ## Returns
    - {:ok, log} on success
    - {:error, changeset} on failure
  """
  def create_sync_log(attrs) do
    result =
      %NotionSyncLog{}
      |> NotionSyncLog.changeset(attrs)
      |> Repo.insert()

    # Broadcast reload signal after successful log creation
    case result do
      {:ok, log} ->
        broadcast_sync_log_created(log.character_id)
        {:ok, log}

      error ->
        error
    end
  end

  # Broadcasts a reload signal for notion_sync_logs to the character's campaign channel
  defp broadcast_sync_log_created(character_id) do
    case Characters.get_character(character_id) do
      nil ->
        :ok

      character ->
        Phoenix.PubSub.broadcast(
          ShotElixir.PubSub,
          "campaign:#{character.campaign_id}",
          {:campaign_broadcast, %{notion_sync_logs: "reload", character_id: character_id}}
        )
    end
  end

  @doc """
  Logs a successful sync operation.
  """
  def log_success(character_id, payload, response) do
    create_sync_log(%{
      character_id: character_id,
      status: "success",
      payload: payload,
      response: response
    })
  end

  @doc """
  Logs a failed sync operation.
  """
  def log_error(character_id, payload, response, error_message) do
    create_sync_log(%{
      character_id: character_id,
      status: "error",
      payload: payload,
      response: response,
      error_message: error_message
    })
  end

  @doc """
  Lists sync logs for a character with pagination.

  ## Parameters
    - character_id: The character's UUID
    - params: Map with optional "page" and "per_page" keys

  ## Returns
    - Map with :logs, :meta keys
  """
  def list_sync_logs_for_character(character_id, params \\ %{}) do
    per_page = get_pagination_param(params, "per_page", 10)
    page = get_pagination_param(params, "page", 1)
    offset = (page - 1) * per_page

    base_query =
      NotionSyncLog
      |> where([l], l.character_id == ^character_id)

    total_count = Repo.aggregate(base_query, :count, :id)

    logs =
      base_query
      |> order_by([l], desc: l.created_at)
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    %{
      logs: logs,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      }
    }
  end

  @doc """
  Gets a single sync log by ID.
  """
  def get_sync_log(id) do
    Repo.get(NotionSyncLog, id)
  end

  @doc """
  Gets a sync log by ID, scoped to a character.
  """
  def get_sync_log_for_character(character_id, log_id) do
    NotionSyncLog
    |> where([l], l.id == ^log_id and l.character_id == ^character_id)
    |> Repo.one()
  end

  # Private helper for pagination params
  defp get_pagination_param(params, key, default) do
    case params[key] do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end
end
