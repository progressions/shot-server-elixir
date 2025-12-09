defmodule ShotElixir.Discord.CurrentCampaign do
  @moduledoc """
  Agent that stores the current campaign for each Discord server.
  Maps server_id -> campaign_id
  """
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Gets the current campaign for a server.
  """
  def get(server_id) when is_integer(server_id) do
    campaign_id = Agent.get(__MODULE__, &Map.get(&1, server_id))

    if campaign_id do
      ShotElixir.Campaigns.get_campaign(campaign_id)
    else
      nil
    end
  end

  def get(nil), do: nil

  @doc """
  Sets the current campaign for a server.
  """
  def set(server_id, campaign_id) when is_integer(server_id) do
    Agent.update(__MODULE__, &Map.put(&1, server_id, campaign_id))
  end

  def set(server_id, nil) when is_integer(server_id) do
    Agent.update(__MODULE__, &Map.delete(&1, server_id))
  end
end
