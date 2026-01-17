defmodule ShotElixir.Notion do
  @moduledoc """
  The Notion context - handles Notion sync logging and related operations.
  """

  import Ecto.Query, warn: false
  require Logger
  alias ShotElixir.Repo
  alias ShotElixir.Notion.NotionSyncLog
  alias ShotElixir.Adventures
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Factions
  alias ShotElixir.Junctures
  alias ShotElixir.Parties
  alias ShotElixir.Sites

  # Notion failure threshold configuration
  # Only notify after N failures within a time window to avoid "ping-pong" notifications
  @failure_threshold Application.compile_env(:shot_elixir, [:notion, :failure_threshold], 3)
  @failure_window_hours Application.compile_env(:shot_elixir, [:notion, :failure_window_hours], 1)

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
  Also resets the campaign's notion_status to "working" if it was "needs_attention".
  """
  def log_success(entity_type, entity_id, payload, response) do
    # Reset campaign status to working if it was needs_attention
    maybe_reset_campaign_status(entity_type, entity_id)

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
  Also sets the campaign's notion_status to "needs_attention".
  """
  def log_error(entity_type, entity_id, payload, response, error_message) do
    # Set campaign status to needs_attention on sync failure
    set_campaign_needs_attention(entity_type, entity_id)

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

  # Sets the campaign's notion_status to "needs_attention" when a sync fails.
  # Uses a threshold system: only notifies after N failures within a time window.
  defp set_campaign_needs_attention(entity_type, entity_id) do
    case get_campaign_for_entity(entity_type, entity_id) do
      nil ->
        :ok

      %{notion_status: "needs_attention"} ->
        # Already needs_attention, don't send another email
        :ok

      campaign ->
        handle_sync_failure(campaign)
    end
  end

  # Handles sync failure with threshold logic to avoid "ping-pong" notifications.
  # Only notifies after @failure_threshold failures within @failure_window_hours.
  defp handle_sync_failure(campaign) do
    now = DateTime.utc_now()
    window_cutoff = DateTime.add(now, -@failure_window_hours, :hour)

    # Check if we need to reset the window (no previous window or window expired)
    {new_count, new_window_start} =
      if is_nil(campaign.notion_failure_window_start) or
           DateTime.compare(campaign.notion_failure_window_start, window_cutoff) == :lt do
        # Start new window
        {1, now}
      else
        # Continue existing window
        {campaign.notion_failure_count + 1, campaign.notion_failure_window_start}
      end

    attrs = %{
      notion_failure_count: new_count,
      notion_failure_window_start: new_window_start
    }

    # Only set needs_attention and email if threshold reached
    attrs =
      if new_count >= @failure_threshold do
        Map.put(attrs, :notion_status, "needs_attention")
      else
        attrs
      end

    case Campaigns.update_campaign(campaign, attrs) do
      {:ok, _updated} when new_count >= @failure_threshold ->
        Logger.info(
          "Notion: Campaign #{campaign.id} reached failure threshold (#{new_count}/#{@failure_threshold}), " <>
            "setting status to needs_attention"
        )

        queue_status_change_email(campaign.id, "needs_attention")

      {:ok, _updated} ->
        Logger.debug(
          "Notion: Campaign #{campaign.id} failure count: #{new_count}/#{@failure_threshold} " <>
            "within window (not notifying yet)"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Notion: Failed to update failure tracking for campaign #{campaign.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  # Resets the campaign's notion_status to "working" if it was "needs_attention"
  # and always resets the failure tracking counters on successful sync.
  defp maybe_reset_campaign_status(entity_type, entity_id) do
    case get_campaign_for_entity(entity_type, entity_id) do
      nil ->
        :ok

      campaign ->
        reset_failure_tracking(campaign)
    end
  end

  # Resets failure tracking and optionally updates status to "working".
  # Always resets counters on success to prevent old failures from accumulating.
  defp reset_failure_tracking(campaign) do
    was_needs_attention = campaign.notion_status == "needs_attention"

    attrs = %{
      notion_failure_count: 0,
      notion_failure_window_start: nil
    }

    attrs =
      if was_needs_attention do
        Map.put(attrs, :notion_status, "working")
      else
        attrs
      end

    case Campaigns.update_campaign(campaign, attrs) do
      {:ok, _updated} when was_needs_attention ->
        Logger.info("Notion: Campaign #{campaign.id} sync succeeded, resetting status to working")
        queue_status_change_email(campaign.id, "working")

      {:ok, _updated} ->
        Logger.debug("Notion: Campaign #{campaign.id} sync succeeded, resetting failure tracking")
        :ok

      {:error, reason} ->
        Logger.error(
          "Notion: Failed to reset failure tracking for campaign #{campaign.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  @doc """
  Queues an email notification for Notion status change.
  Used by both Notion sync operations and OAuth controller.
  """
  def queue_status_change_email(campaign_id, new_status) do
    job =
      %{
        "type" => "notion_status_changed",
        "campaign_id" => campaign_id,
        "new_status" => new_status
      }
      |> ShotElixir.Workers.EmailWorker.new()

    case Oban.insert(job) do
      {:ok, _job} = ok ->
        ok

      {:error, reason} = error ->
        Logger.error(
          "Notion: Failed to queue status change email for campaign #{campaign_id} " <>
            "to status #{inspect(new_status)}: #{inspect(reason)}"
        )

        error
    end
  end

  # Gets the campaign for an entity using an optimized single query
  defp get_campaign_for_entity(entity_type, entity_id) do
    schema = entity_type_to_schema(entity_type)

    if schema do
      # Single query with join to get campaign directly
      query =
        from e in schema,
          join: c in Campaigns.Campaign,
          on: c.id == e.campaign_id,
          where: e.id == ^entity_id,
          select: c

      Repo.one(query)
    else
      nil
    end
  end

  # Maps entity type strings to their Ecto schema modules
  defp entity_type_to_schema(entity_type) do
    case entity_type do
      "character" -> ShotElixir.Characters.Character
      "site" -> ShotElixir.Sites.Site
      "party" -> ShotElixir.Parties.Party
      "faction" -> ShotElixir.Factions.Faction
      "juncture" -> ShotElixir.Junctures.Juncture
      "adventure" -> ShotElixir.Adventures.Adventure
      _ -> nil
    end
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
