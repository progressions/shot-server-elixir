defmodule ShotElixirWeb.Api.V2.NotionSyncLogController do
  @moduledoc """
  Controller for Notion sync log operations.
  Access is restricted to admins and campaign gamemasters.
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Characters
  alias ShotElixir.Campaigns
  alias ShotElixir.Notion
  alias ShotElixir.Guardian
  alias ShotElixir.Sites
  alias ShotElixir.Parties
  alias ShotElixir.Factions

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  GET /api/v2/:entity_type/:entity_id/notion_sync_logs

  Lists Notion sync logs for an entity (character, site, party, faction).
  Only accessible to admins or the campaign's gamemaster.
  """
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    {entity_type, entity_id} = get_entity_from_params(params)

    with {:ok, entity} <- fetch_entity(entity_type, entity_id),
         :ok <- authorize_admin_access(entity, current_user) do
      %{logs: logs, meta: meta} = Notion.list_sync_logs(entity_type, entity_id, params)

      conn
      |> put_view(ShotElixirWeb.Api.V2.NotionSyncLogView)
      |> render("index.json", logs: logs, meta: meta)
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  DELETE /api/v2/:entity_type/:entity_id/notion_sync_logs/prune

  Prunes (deletes) old Notion sync logs for an entity.
  Only accessible to admins or the campaign's gamemaster.

  ## Parameters
    - days_old: Number of days old logs must be to be deleted (default: 30)
  """
  def prune(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    {entity_type, entity_id} = get_entity_from_params(params)

    with {:ok, entity} <- fetch_entity(entity_type, entity_id),
         :ok <- authorize_admin_access(entity, current_user) do
      days_old = parse_days_old(params["days_old"])
      {:ok, count} = Notion.prune_sync_logs(entity_type, entity_id, days_old: days_old)

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

  defp get_entity_from_params(params) do
    cond do
      Map.has_key?(params, "character_id") -> {"character", params["character_id"]}
      Map.has_key?(params, "site_id") -> {"site", params["site_id"]}
      Map.has_key?(params, "party_id") -> {"party", params["party_id"]}
      Map.has_key?(params, "faction_id") -> {"faction", params["faction_id"]}
      true -> {nil, nil}
    end
  end

  defp fetch_entity("character", id) do
    case Characters.get_character(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp fetch_entity("site", id) do
    case Sites.get_site(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp fetch_entity("party", id) do
    case Parties.get_party(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp fetch_entity("faction", id) do
    case Factions.get_faction(id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  defp fetch_entity(_, _), do: {:error, :not_found}

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
end
