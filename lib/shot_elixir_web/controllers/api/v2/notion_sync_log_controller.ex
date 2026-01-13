defmodule ShotElixirWeb.Api.V2.NotionSyncLogController do
  @moduledoc """
  Controller for Notion sync log operations.
  Access is restricted to admins and campaign gamemasters.
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Factions
  alias ShotElixir.Junctures
  alias ShotElixir.Parties
  alias ShotElixir.Sites
  alias ShotElixir.Notion
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  @entity_fetchers %{
    "character_id" => {"character", Characters, :get_character},
    "site_id" => {"site", Sites, :get_site},
    "party_id" => {"party", Parties, :get_party},
    "faction_id" => {"faction", Factions, :get_faction},
    "juncture_id" => {"juncture", Junctures, :get_juncture}
  }

  @doc """
  GET /api/v2/:entity/:id/notion_sync_logs

  Lists Notion sync logs for an entity.
  Only accessible to admins or the campaign's gamemaster.
  """
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, entity_type, entity} <- fetch_entity(params),
         :ok <- authorize_admin_access(entity, current_user) do
      %{logs: logs, meta: meta} = Notion.list_sync_logs(entity_type, entity.id, params)

      conn
      |> put_view(ShotElixirWeb.Api.V2.NotionSyncLogView)
      |> render("index.json", logs: logs, meta: meta)
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  DELETE /api/v2/:entity/:id/notion_sync_logs/prune

  Prunes (deletes) old Notion sync logs for an entity.
  Only accessible to admins or the campaign's gamemaster.

  ## Parameters
    - days_old: Number of days old logs must be to be deleted (default: 30)
  """
  def prune(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, entity_type, entity} <- fetch_entity(params),
         :ok <- authorize_admin_access(entity, current_user) do
      days_old = parse_days_old(params["days_old"])
      {:ok, count} = Notion.prune_sync_logs(entity_type, entity.id, days_old: days_old)

      conn
      |> put_view(ShotElixirWeb.Api.V2.NotionSyncLogView)
      |> render("prune.json", count: count, days_old: days_old)
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_days_old(nil), do: 30

  defp parse_days_old(value) when is_integer(value), do: max(1, value)

  defp parse_days_old(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> max(1, int)
      _ -> 30
    end
  end

  # Private helper to check admin/gamemaster access
  defp authorize_admin_access(entity, user) do
    campaign = Campaigns.get_campaign(entity.campaign_id)

    cond do
      user.admin ->
        :ok

      is_nil(campaign) ->
        {:error, :not_found}

      campaign.user_id == user.id ->
        :ok

      user.gamemaster && Campaigns.is_member?(campaign.id, user.id) ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  defp fetch_entity(params) do
    # Find the first parameter that matches our known entity IDs
    key = Enum.find(Map.keys(@entity_fetchers), &Map.has_key?(params, &1))

    case Map.get(@entity_fetchers, key) do
      {type, mod, fun} ->
        id = Map.get(params, key)

        case apply(mod, fun, [id]) do
          nil -> {:error, :not_found}
          entity -> {:ok, type, entity}
        end

      nil ->
        {:error, :not_found}
    end
  end
end
