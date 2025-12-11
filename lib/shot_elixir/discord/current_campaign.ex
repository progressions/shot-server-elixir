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
    case Agent.get(__MODULE__, &Map.get(&1, server_id, :not_cached)) do
      :not_cached ->
        # Load from database and cache
        campaign = ServerSettings.get_current_campaign(server_id)
        campaign_id = if campaign, do: campaign.id, else: nil
        Agent.update(__MODULE__, &Map.put(&1, server_id, campaign_id))
        campaign

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
  """
  def set(server_id, campaign_id) when is_integer(server_id) do
    # Update database first (source of truth)
    ServerSettings.set_current_campaign(server_id, campaign_id)

    # Then update cache
    case campaign_id do
      nil -> Agent.update(__MODULE__, &Map.put(&1, server_id, nil))
      _ -> Agent.update(__MODULE__, &Map.put(&1, server_id, campaign_id))
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
