defmodule ShotElixir.Discord.CurrentCampaign do
  @moduledoc """
  Agent that caches the current campaign for each Discord server.
  Maps server_id -> campaign_id

  Uses database as source of truth with in-memory caching for performance.
  Settings persist across server restarts via the ServerSettings context.
  """
  use Agent

  alias ShotElixir.Discord.ServerSettings
  alias ShotElixir.Campaigns

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Gets the current campaign for a server.

  First checks the in-memory cache, then falls back to database.
  """
  def get(server_id) when is_integer(server_id) do
    # Check cache first (atomic read)
    case Agent.get(__MODULE__, &Map.get(&1, server_id, :not_cached)) do
      :not_cached ->
        # Cache miss - load from database
        campaign = ServerSettings.get_current_campaign(server_id)
        campaign_id = if campaign, do: campaign.id, else: nil

        # Update cache atomically - use get_and_update to check if another
        # process already cached a value while we were loading from DB
        Agent.get_and_update(__MODULE__, fn state ->
          case Map.get(state, server_id, :not_cached) do
            :not_cached ->
              # Still not cached, use our value
              {campaign, Map.put(state, server_id, campaign_id)}

            existing_id ->
              # Another process cached a value, use that instead
              {existing_id, state}
          end
        end)
        |> case do
          %ShotElixir.Campaigns.Campaign{} = c -> c
          nil -> nil
          cached_id -> Campaigns.get_campaign(cached_id)
        end

      nil ->
        nil

      campaign_id ->
        Campaigns.get_campaign(campaign_id)
    end
  end

  def get(nil), do: nil

  @doc """
  Sets the current campaign for a server.

  Updates both the database (source of truth) and the in-memory cache.
  Pass nil as campaign_id to clear the current campaign.
  Only updates cache if database update succeeds.
  """
  def set(server_id, campaign_id) when is_integer(server_id) do
    # Update database first (source of truth)
    case ServerSettings.set_current_campaign(server_id, campaign_id) do
      {:ok, _setting} ->
        # Only update cache if database update succeeded
        Agent.update(__MODULE__, &Map.put(&1, server_id, campaign_id))
        :ok

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Clears the cache for a specific server (for testing or cache invalidation).
  """
  def clear_cache(server_id) when is_integer(server_id) do
    Agent.update(__MODULE__, &Map.delete(&1, server_id))
  end

  @doc """
  Clears entire cache (for testing).
  """
  def clear_all_cache do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
