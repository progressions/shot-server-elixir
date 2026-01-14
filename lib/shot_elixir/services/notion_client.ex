defmodule ShotElixir.Services.NotionClient do
  @moduledoc """
  HTTP client for Notion API v1.
  Uses Req library for HTTP requests.
  """

  @notion_version "2025-09-03"
  @base_url "https://api.notion.com/v1"

  def client do
    # Read token directly from environment at runtime since Dotenvy
    # loads .env after config is compiled
    token =
      System.get_env("NOTION_TOKEN") ||
        Application.get_env(:shot_elixir, :notion)[:token]

    unless token do
      raise "NOTION_TOKEN environment variable is not set"
    end

    Req.new(
      base_url: @base_url,
      headers: [
        {"Authorization", "Bearer #{token}"},
        {"Notion-Version", @notion_version},
        {"Content-Type", "application/json"}
      ]
    )
  end

  def search(query, opts \\ %{}) do
    body = Map.merge(%{"query" => query}, opts)

    client()
    |> Req.post!(url: "/search", json: body)
    |> Map.get(:body)
  end

  def data_source_query(data_source_id, opts \\ %{}) do
    client()
    |> Req.post!(url: "/data_sources/#{data_source_id}/query", json: opts)
    |> Map.get(:body)
  end

  def create_page(params) do
    client()
    |> Req.post!(url: "/pages", json: params)
    |> Map.get(:body)
  end

  def update_page(page_id, properties) do
    client()
    |> Req.patch!(url: "/pages/#{page_id}", json: %{"properties" => properties})
    |> Map.get(:body)
  end

  def get_page(page_id) do
    client()
    |> Req.get!(url: "/pages/#{page_id}")
    |> Map.get(:body)
  end

  def get_database(database_id) do
    client()
    |> Req.get!(url: "/databases/#{database_id}")
    |> Map.get(:body)
  end

  def get_block_children(block_id) do
    client()
    |> Req.get!(url: "/blocks/#{block_id}/children")
    |> Map.get(:body)
  end

  def append_block_children(block_id, children) do
    client()
    |> Req.patch!(url: "/blocks/#{block_id}/children", json: %{"children" => children})
    |> Map.get(:body)
  end
end
