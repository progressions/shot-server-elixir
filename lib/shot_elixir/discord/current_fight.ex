defmodule ShotElixir.Discord.CurrentFight do
  @moduledoc """
  Manages the current fight for each Discord server.
  Stores server_id -> fight_id mappings with database persistence.

  Uses database as source of truth with in-memory caching for performance.
  Settings persist across server restarts via the ServerSettings context.
  """
  use Agent

  alias ShotElixir.Discord.ServerSettings

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Sets the current fight for a Discord server.

  Updates both the database (source of truth) and the in-memory cache.
  """
  def set(server_id, fight_id) when is_binary(fight_id) or is_nil(fight_id) do
    # Update database first (source of truth)
    ServerSettings.set_current_fight(server_id, fight_id)

    # Then update cache
    Agent.update(__MODULE__, fn state ->
      case fight_id do
        nil -> Map.put(state, server_id, nil)
        id -> Map.put(state, server_id, id)
      end
    end)
  end

  @doc """
  Gets the current fight ID for a Discord server.

  First checks the in-memory cache, then falls back to database.
  """
  def get(server_id) do
    case Agent.get(__MODULE__, &Map.get(&1, server_id, :not_cached)) do
      :not_cached ->
        # Load from database and cache
        fight_id = ServerSettings.get_current_fight_id(server_id)
        Agent.update(__MODULE__, &Map.put(&1, server_id, fight_id))
        fight_id

      cached_value ->
        cached_value
    end
  end

  @doc """
  Gets all current fights from cache (for debugging/monitoring).
  """
  def all do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Clears the cache for a specific server (for testing or cache invalidation).
  """
  def clear_cache(server_id) do
    Agent.update(__MODULE__, &Map.delete(&1, server_id))
  end

  @doc """
  Clears entire cache (for testing).
  """
  def clear_all_cache do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
