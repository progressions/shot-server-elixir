defmodule ShotElixir.Discord.ServerSettings do
  @moduledoc """
  Context for managing Discord server settings.

  Provides database-backed persistence for per-server configuration,
  replacing volatile in-memory state with durable storage.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Discord.ServerSetting
  alias ShotElixir.Campaigns
  alias ShotElixir.Fights

  @doc """
  Gets or creates server settings for a Discord server.

  Returns the ServerSetting struct for the given server_id,
  creating a new record if one doesn't exist.
  """
  def get_or_create_settings(server_id) when is_integer(server_id) do
    case Repo.get_by(ServerSetting, server_id: server_id) do
      nil ->
        # Use upsert to handle race conditions - if another process inserts
        # between our get_by and insert, we'll update instead of crash
        %ServerSetting{}
        |> ServerSetting.changeset(%{server_id: server_id})
        |> Repo.insert(
          on_conflict: :nothing,
          conflict_target: :server_id
        )
        |> case do
          {:ok, setting} -> setting
          # If on_conflict fired, fetch the existing record
          {:error, _} -> Repo.get_by!(ServerSetting, server_id: server_id)
        end

      setting ->
        setting
    end
  end

  @doc """
  Gets the current campaign for a server, returning the full campaign struct.

  Returns nil if no campaign is set.
  """
  def get_current_campaign(server_id) when is_integer(server_id) do
    case get_setting_field(server_id, :current_campaign_id) do
      nil -> nil
      campaign_id -> Campaigns.get_campaign(campaign_id)
    end
  end

  @doc """
  Gets the current campaign ID for a server.

  Returns nil if no campaign is set.
  """
  def get_current_campaign_id(server_id) when is_integer(server_id) do
    get_setting_field(server_id, :current_campaign_id)
  end

  @doc """
  Sets the current campaign for a server.

  Pass nil to clear the current campaign.
  """
  def set_current_campaign(server_id, campaign_id) when is_integer(server_id) do
    update_server_setting(server_id, %{current_campaign_id: campaign_id})
  end

  @doc """
  Gets the current fight ID for a server.

  Returns nil if no fight is set.
  """
  def get_current_fight_id(server_id) when is_integer(server_id) do
    get_setting_field(server_id, :current_fight_id)
  end

  @doc """
  Gets the current fight for a server, returning the full fight struct.

  Returns nil if no fight is set.
  """
  def get_current_fight(server_id) when is_integer(server_id) do
    case get_current_fight_id(server_id) do
      nil -> nil
      fight_id -> Fights.get_fight(fight_id)
    end
  end

  @doc """
  Sets the current fight for a server.

  Pass nil to clear the current fight.
  """
  def set_current_fight(server_id, fight_id) when is_integer(server_id) do
    update_server_setting(server_id, %{current_fight_id: fight_id})
  end

  @doc """
  Gets a custom setting from the settings map.
  """
  def get_custom_setting(server_id, key) when is_integer(server_id) and is_binary(key) do
    case get_setting_field(server_id, :settings) do
      nil -> nil
      settings -> Map.get(settings, key)
    end
  end

  @doc """
  Sets a custom setting in the settings map.
  """
  def set_custom_setting(server_id, key, value) when is_integer(server_id) and is_binary(key) do
    setting = get_or_create_settings(server_id)
    new_settings = Map.put(setting.settings || %{}, key, value)
    update_server_setting(server_id, %{settings: new_settings})
  end

  @doc """
  Lists all server settings (for debugging/admin purposes).
  """
  def list_all do
    Repo.all(ServerSetting)
    |> Repo.preload([:current_campaign, :current_fight])
  end

  # Private helpers

  defp create_setting(attrs) do
    %ServerSetting{}
    |> ServerSetting.changeset(attrs)
    |> Repo.insert()
  end

  defp get_setting_field(server_id, field) do
    query =
      from s in ServerSetting,
        where: s.server_id == ^server_id,
        select: field(s, ^field)

    Repo.one(query)
  end

  defp update_server_setting(server_id, attrs) do
    setting = get_or_create_settings(server_id)

    setting
    |> ServerSetting.changeset(attrs)
    |> Repo.update()
  end
end
