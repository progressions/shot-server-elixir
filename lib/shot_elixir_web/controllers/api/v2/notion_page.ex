defmodule ShotElixirWeb.Api.V2.NotionPage do
  @moduledoc """
  Shared helper for fetching raw Notion page JSON for entities.

  Used by controllers to implement GET /:id/notion_page endpoints
  that return the raw Notion API response for debugging purposes.
  """

  import Plug.Conn
  import Phoenix.Controller
  require Logger

  alias ShotElixir.Services.NotionClient
  alias ShotElixir.Services.NotionService

  @doc """
  Fetches and returns the raw Notion page JSON for an entity.

  ## Options

    * `:authorize` - Function that takes (campaign, user) and returns boolean
    * `:entity_name` - Human-readable entity name for error messages (e.g., "Character")

  ## Returns

  The raw JSON response from Notion's GET /pages/:id endpoint.
  """
  def fetch(conn, current_user, entity, campaign, opts) do
    entity_name = Keyword.get(opts, :entity_name, "Entity")
    authorize_fn = Keyword.fetch!(opts, :authorize)

    cond do
      # Check authorization
      not authorize_fn.(campaign, current_user) ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})

      # Check entity has a notion_page_id
      is_nil(entity.notion_page_id) or entity.notion_page_id == "" ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "#{entity_name} has no linked Notion page"})

      true ->
        # Get the campaign's Notion OAuth token
        token = NotionService.get_token(campaign)

        if is_nil(token) or token == "" do
          conn
          |> put_status(:not_found)
          |> json(%{error: "Notion not connected for this campaign"})
        else
          fetch_notion_page(conn, entity.notion_page_id, token)
        end
    end
  end

  defp fetch_notion_page(conn, page_id, token) do
    try do
      case NotionClient.get_page(page_id, token: token) do
        %{"code" => error_code, "message" => message} ->
          Logger.warning("Notion API error fetching page #{page_id}: #{error_code} - #{message}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Notion API error: #{message}"})

        page when is_map(page) ->
          conn
          |> put_status(:ok)
          |> json(page)
      end
    rescue
      e in Mint.TransportError ->
        Logger.error("Notion API transport error: #{Exception.message(e)}")

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Failed to connect to Notion API"})

      e in RuntimeError ->
        Logger.error("Notion API runtime error: #{Exception.message(e)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to fetch Notion page"})

      e ->
        Logger.error("Unexpected error fetching Notion page: #{Exception.message(e)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "An unexpected error occurred"})
    end
  end
end
