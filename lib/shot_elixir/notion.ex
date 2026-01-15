defmodule ShotElixir.Notion do
  @moduledoc """
  The Notion context - handles Notion sync logging and related operations.
  """

  import Ecto.Query, warn: false
  require Logger
  alias ShotElixir.Repo
  alias ShotElixir.Notion.NotionSyncLog
  alias ShotElixir.Adventures
  alias ShotElixir.Characters
  alias ShotElixir.Factions
  alias ShotElixir.Junctures
  alias ShotElixir.Parties
  alias ShotElixir.Sites

  @doc """
  Creates a sync log entry.

  ## Parameters
    - attrs: Map with :entity_type, :entity_id, :status, :payload, :response, :error_message

  ## Returns
    - {:ok, log} on success
    - {:error, changeset} on failure
  """
  def create_sync_log(attrs) do
    attrs = maybe_set_character_id(attrs)

    result =
      %NotionSyncLog{}
      |> NotionSyncLog.changeset(attrs)
      |> Repo.insert()

    # Broadcast reload signal after successful log creation
    case result do
      {:ok, log} ->
        broadcast_sync_log_created(log.entity_type, log.entity_id)
        {:ok, log}

      error ->
        error
    end
  end

  defp maybe_set_character_id(%{entity_type: "character", entity_id: entity_id} = attrs) do
    Map.put_new(attrs, :character_id, entity_id)
  end

  defp maybe_set_character_id(attrs), do: attrs

  # Broadcasts a reload signal for notion_sync_logs to the entity's campaign channel
  defp broadcast_sync_log_created(entity_type, entity_id) do
    campaign_id =
      case entity_type do
        "character" ->
          case Characters.get_character(entity_id) do
            nil -> nil
            character -> character.campaign_id
          end

        "site" ->
          case Sites.get_site(entity_id) do
            nil -> nil
            site -> site.campaign_id
          end

        "party" ->
          case Parties.get_party(entity_id) do
            nil -> nil
            party -> party.campaign_id
          end

        "faction" ->
          case Factions.get_faction(entity_id) do
            nil -> nil
            faction -> faction.campaign_id
          end

        "juncture" ->
          case Junctures.get_juncture(entity_id) do
            nil -> nil
            juncture -> juncture.campaign_id
          end

        "adventure" ->
          case Adventures.get_adventure(entity_id) do
            nil -> nil
            adventure -> adventure.campaign_id
          end

        _ ->
          nil
      end

    if campaign_id do
      Phoenix.PubSub.broadcast(
        ShotElixir.PubSub,
        "campaign:#{campaign_id}",
        {:campaign_broadcast, %{notion_sync_logs: "reload"}}
      )
    else
      Logger.warning("Cannot broadcast sync log created: #{entity_type} #{entity_id} not found")

      :ok
    end
  end

  @doc """
  Logs a successful sync operation.
  """
  def log_success(entity_type, entity_id, payload, response) do
    create_sync_log(%{
      entity_type: entity_type,
      entity_id: entity_id,
      status: "success",
      payload: payload,
      response: response
    })
  end

  @doc """
  Logs a failed sync operation.
  """
  def log_error(entity_type, entity_id, payload, response, error_message) do
    create_sync_log(%{
      entity_type: entity_type,
      entity_id: entity_id,
      status: "error",
      payload: payload,
      response: response,
      error_message: error_message
    })
  end

  @doc """
  Lists sync logs for an entity with pagination.

  ## Parameters
    - entity_type: The entity type ("character", "site", "party", "faction")
    - entity_id: The entity's UUID
    - params: Map with optional "page" and "per_page" keys

  ## Returns
    - Map with :logs, :meta keys
  """
  def list_sync_logs(entity_type, entity_id, params \\ %{}) do
    per_page = get_pagination_param(params, "per_page", 10)
    page = get_pagination_param(params, "page", 1)
    offset = (page - 1) * per_page

    base_query =
      NotionSyncLog
      |> where([l], l.entity_type == ^entity_type and l.entity_id == ^entity_id)

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

  def list_sync_logs_for_character(character_id, params \\ %{}) do
    list_sync_logs("character", character_id, params)
  end

  @doc """
  Gets a single sync log by ID.
  """
  def get_sync_log(id) do
    Repo.get(NotionSyncLog, id)
  end

  @doc """
  Gets a sync log by ID, scoped to an entity.
  """
  def get_sync_log_for_entity(entity_type, entity_id, log_id) do
    NotionSyncLog
    |> where([l], l.id == ^log_id and l.entity_type == ^entity_type and l.entity_id == ^entity_id)
    |> Repo.one()
  end

  def get_sync_log_for_character(character_id, log_id) do
    get_sync_log_for_entity("character", character_id, log_id)
  end

  @doc """
  Prunes (deletes) old sync logs for an entity.

  ## Parameters
    - entity_type: The entity type ("character", "site", "party", "faction")
    - entity_id: The entity's UUID
    - opts: Keyword list with optional :days_old (default 30)

  ## Returns
    - {:ok, count} with the number of deleted logs
  """
  def prune_sync_logs(entity_type, entity_id, opts \\ []) do
    days_old = Keyword.get(opts, :days_old, 30)
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days_old, :day)

    {count, _} =
      NotionSyncLog
      |> where([l], l.entity_type == ^entity_type and l.entity_id == ^entity_id)
      |> where([l], l.created_at < ^cutoff_date)
      |> Repo.delete_all()

    {:ok, count}
  end

  def prune_sync_logs_for_character(character_id, opts \\ []) do
    prune_sync_logs("character", character_id, opts)
  end

  # Private helper for pagination params
  defp get_pagination_param(params, key, default) do
    case params[key] do
      nil ->
        default

      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end
    end
  end
end
