defmodule ShotElixirWeb.Api.V2.NotionSyncLogView do
  @moduledoc """
  View for rendering Notion sync log JSON responses.
  """

  def render("index.json", %{logs: logs, meta: meta}) do
    %{
      notion_sync_logs: Enum.map(logs, &render_log/1),
      meta: meta
    }
  end

  def render("show.json", %{log: log}) do
    render_log(log)
  end

  def render("prune.json", %{count: count, days_old: days_old}) do
    %{
      pruned_count: count,
      days_old: days_old,
      message: "Deleted #{count} sync log(s) older than #{days_old} days"
    }
  end

  defp render_log(log) do
    %{
      id: log.id,
      status: log.status,
      payload: log.payload,
      response: log.response,
      error_message: log.error_message,
      entity_type: log.entity_type,
      entity_id: log.entity_id,
      character_id: log.character_id,
      created_at: log.created_at,
      updated_at: log.updated_at
    }
  end
end
