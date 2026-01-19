defmodule ShotElixir.Services.Notion.Config do
  @moduledoc """
  Configuration and cached lookups for Notion integrations.

  Responsibilities:
  - Resolve OAuth tokens and database IDs from campaigns
  - Cache data_source IDs and bot user IDs in ETS
  - Provide a shared Notion client accessor with optional overrides
  """

  require Logger

  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Services.NotionClient

  @data_source_cache_table :notion_data_source_cache

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def get_token(%Campaign{} = campaign) do
    campaign.notion_access_token ||
      System.get_env("NOTION_TOKEN") ||
      Application.get_env(:shot_elixir, :notion)[:token]
  end

  def get_token(_campaign_id) do
    System.get_env("NOTION_TOKEN") || Application.get_env(:shot_elixir, :notion)[:token]
  end

  def get_database_id_for_entity(%Campaign{notion_database_ids: nil}, entity_type) do
    Logger.warning("Campaign has no notion_database_ids configured for #{entity_type}")
    {:error, :no_database_configured}
  end

  def get_database_id_for_entity(%Campaign{notion_database_ids: db_ids}, entity_type)
      when is_map(db_ids) do
    case Map.get(db_ids, entity_type) do
      nil ->
        Logger.warning("No Notion database ID configured for #{entity_type}")
        {:error, :no_database_configured}

      database_id when is_binary(database_id) ->
        {:ok, database_id}
    end
  end

  def get_database_id_for_entity(_campaign, entity_type) do
    Logger.warning("Invalid campaign or notion_database_ids for #{entity_type}")
    {:error, :no_database_configured}
  end

  def init_data_source_cache do
    _ = data_source_cache_table()
    :ok
  end

  def data_source_id_for(database_id, opts \\ []) do
    case cached_data_source_id(database_id) do
      {:ok, data_source_id} ->
        {:ok, data_source_id}

      :miss ->
        client = client(opts)
        token = Keyword.get(opts, :token)

        # Use get_data_source instead of get_database for Notion API 2025-09-03
        # The database_id can be used directly as the data_source_id
        case client.get_data_source(database_id, %{token: token}) do
          %{"data_sources" => data_sources} when is_list(data_sources) ->
            case extract_data_source_id(data_sources) do
              nil ->
                {:error, :notion_data_source_missing}

              data_source_id ->
                cache_data_source_id(database_id, data_source_id)
                {:ok, data_source_id}
            end

          %{"data_source_id" => data_source_id} when is_binary(data_source_id) ->
            cache_data_source_id(database_id, data_source_id)
            {:ok, data_source_id}

          %{"data_source" => %{"id" => data_source_id}} when is_binary(data_source_id) ->
            cache_data_source_id(database_id, data_source_id)
            {:ok, data_source_id}

          # Handle standard data_source response where "id" is the data_source_id
          %{"id" => data_source_id, "object" => "data_source"} when is_binary(data_source_id) ->
            cache_data_source_id(database_id, data_source_id)
            {:ok, data_source_id}

          %{"code" => error_code, "message" => message} ->
            Logger.error(
              "Notion get_data_source error for database_id=#{database_id}: " <>
                "#{error_code} - #{message}"
            )

            {:error, {:notion_api_error, error_code, message}}

          nil ->
            Logger.error("Notion get_data_source returned nil for database_id=#{database_id}")
            {:error, :notion_data_source_not_found}

          response ->
            Logger.error(
              "Unexpected response from Notion get_data_source for database_id=#{database_id}: " <>
                "#{inspect(response)}"
            )

            {:error, {:unexpected_notion_response, response}}
        end
    end
  end

  def get_bot_user_id(opts \\ []) do
    token = Keyword.get(opts, :token)
    key = {:bot_user_id, token}
    table = data_source_cache_table()
    client = client(opts)
    opts_map = Enum.into(opts, %{})

    case :ets.lookup(table, key) do
      [{^key, bot_id}] ->
        {:ok, bot_id}

      [] ->
        case client.get_me(opts_map) do
          %{"id" => bot_id} ->
            :ets.insert(table, {key, bot_id})
            {:ok, bot_id}

          _ ->
            {:error, :failed_to_fetch_bot_id}
        end
    end
  end

  def skip_bot_update?(page, opts \\ []) do
    case get_bot_user_id(opts) do
      {:ok, bot_id} ->
        get_in(page, ["last_edited_by", "id"]) == bot_id

      _ ->
        false
    end
  end

  def client(opts \\ []), do: Keyword.get(opts, :client, NotionClient)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp data_source_cache_table do
    case :ets.whereis(@data_source_cache_table) do
      :undefined ->
        try do
          :ets.new(@data_source_cache_table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true
          ])
        rescue
          ArgumentError -> @data_source_cache_table
        end

      _ ->
        @data_source_cache_table
    end
  end

  defp cached_data_source_id(database_id) do
    table = data_source_cache_table()

    case :ets.lookup(table, database_id) do
      [{^database_id, data_source_id}] -> {:ok, data_source_id}
      _ -> :miss
    end
  end

  defp cache_data_source_id(database_id, data_source_id) do
    table = data_source_cache_table()
    :ets.insert(table, {database_id, data_source_id})
    :ok
  end

  defp extract_data_source_id(data_sources) do
    Enum.find_value(data_sources, fn
      %{"id" => id} when is_binary(id) -> id
      id when is_binary(id) -> id
      _ -> nil
    end)
  end
end
