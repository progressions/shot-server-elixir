defmodule ShotElixir.Services.NotionClient do
  @moduledoc """
  HTTP client for Notion API v1.
  Uses Req library for HTTP requests.
  """

  @notion_version "2025-09-03"
  @base_url "https://api.notion.com/v1"

  def client(token \\ nil) do
    # Use provided token, then environment, then config
    token =
      token ||
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
    {token, opts} = Map.pop(opts, :token)
    body = Map.merge(%{"query" => query}, opts)

    client(token)
    |> Req.post!(url: "/search", json: body)
    |> Map.get(:body)
  end

  def data_source_query(data_source_id, opts \\ %{}) do
    {token, opts} = Map.pop(opts, :token)

    client(token)
    |> Req.post!(url: "/data_sources/#{data_source_id}/query", json: opts)
    |> Map.get(:body)
  end

  def database_query(database_id, opts \\ %{}) do
    {token, opts} = Map.pop(opts, :token)

    client(token)
    |> Req.post!(url: "/databases/#{database_id}/query", json: opts)
    |> Map.get(:body)
  end

  def create_page(params) do
    {token, params} = Map.pop(params, :token)

    client(token)
    |> Req.post!(url: "/pages", json: params)
    |> Map.get(:body)
  end

  def update_page(page_id, properties, opts \\ %{}) do
    token = Map.get(opts, :token)

    client(token)
    |> Req.patch!(url: "/pages/#{page_id}", json: %{"properties" => properties})
    |> Map.get(:body)
  end

  def get_page(page_id, opts \\ %{}) do
    token = Map.get(opts, :token)

    client(token)
    |> Req.get!(url: "/pages/#{page_id}")
    |> Map.get(:body)
  end

  def get_database(database_id, opts \\ %{}) do
    token = Map.get(opts, :token)

    client(token)
    |> Req.get!(url: "/databases/#{database_id}")
    |> Map.get(:body)
  end

  def get_block_children(block_id, opts \\ %{}) do
    token = Map.get(opts, :token)

    client(token)
    |> Req.get!(url: "/blocks/#{block_id}/children")
    |> Map.get(:body)
  end

  def append_block_children(block_id, children, opts \\ %{}) do
    token = Map.get(opts, :token)

    client(token)
    |> Req.patch!(url: "/blocks/#{block_id}/children", json: %{"children" => children})
    |> Map.get(:body)
  end
end
