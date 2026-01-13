defmodule ShotElixirWeb.Api.V2.SyncFromNotion do
  @moduledoc false

  import Phoenix.Controller
  require Logger

  def sync(conn, current_user, entity, campaign, opts) do
    if opts[:authorize].(campaign, current_user) do
      with :ok <- opts[:require_page].(entity),
           {:ok, updated_entity} <- opts[:update].(entity) do
        conn
        |> put_view(opts[:view])
        |> render("show.json", %{opts[:assign_key] => updated_entity})
      else
        {:error, :no_notion_page} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: opts[:no_page_error]})

        {:error, {:notion_api_error, _code, message}} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to sync from Notion: #{message}"})

        {:error, reason} ->
          Logger.error("Failed to sync from Notion: #{inspect(reason)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to sync from Notion"})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: opts[:forbidden_error]})
    end
  end
end
