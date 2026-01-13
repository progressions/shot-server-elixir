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

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  GET /api/v2/characters/:character_id/notion_sync_logs

  Lists Notion sync logs for a character.
  Only accessible to admins or the campaign's gamemaster.
  """
  def index(conn, %{"character_id" => character_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_admin_access(character, current_user) do
      %{logs: logs, meta: meta} = Notion.list_sync_logs_for_character(character_id, params)

      conn
      |> put_view(ShotElixirWeb.Api.V2.NotionSyncLogView)
      |> render("index.json", logs: logs, meta: meta)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  DELETE /api/v2/characters/:character_id/notion_sync_logs/prune

  Prunes (deletes) old Notion sync logs for a character.
  Only accessible to admins or the campaign's gamemaster.

  ## Parameters
    - days_old: Number of days old logs must be to be deleted (default: 30)
  """
  def prune(conn, %{"character_id" => character_id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_admin_access(character, current_user) do
      days_old = parse_days_old(params["days_old"])
      {:ok, count} = Notion.prune_sync_logs("character", character_id, days_old: days_old)

      conn
      |> put_view(ShotElixirWeb.Api.V2.NotionSyncLogView)
      |> render("prune.json", count: count, days_old: days_old)
    else
      nil -> {:error, :not_found}
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
  defp authorize_admin_access(character, user) do
    campaign = Campaigns.get_campaign(character.campaign_id)

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
