defmodule ShotElixir.Discord.CurrentFight do
  @moduledoc """
  Manages the current fight for each Discord server using an Agent.
  Stores server_id -> fight_id mappings in memory.
  """
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Sets the current fight for a Discord server.
  """
  def set(server_id, fight_id) when is_binary(fight_id) or is_nil(fight_id) do
    Agent.update(__MODULE__, fn state ->
      case fight_id do
        nil -> Map.delete(state, server_id)
        id -> Map.put(state, server_id, id)
      end
    end)
  end

  @doc """
  Gets the current fight ID for a Discord server.
  """
  def get(server_id) do
    Agent.get(__MODULE__, &Map.get(&1, server_id))
  end

  @doc """
  Gets all current fights (for debugging/monitoring).
  """
  def all do
    Agent.get(__MODULE__, & &1)
  end
end
