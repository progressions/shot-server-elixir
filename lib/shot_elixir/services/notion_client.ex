defmodule ShotElixir.Services.NotionClient do
  @moduledoc """
  HTTP client for Notion API v1.
  Uses Req library for HTTP requests.
  """

  @notion_version "2025-09-03"
  @base_url "https://api.notion.com/v1"

  defp require_token(token) do
    if is_binary(token) and token != "" do
      :ok
    else
      {:error, %{"code" => "missing_token", "message" => "Notion OAuth token missing"}}
    end
  end

  # Normalize options: convert keyword lists to maps for consistent handling
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_), do: %{}

  def client(token \\ nil) do
    # Token must be provided (from campaign OAuth). We intentionally do not
    # fall back to environment or application config to avoid accidental use of
    # stale or shared credentials.
    unless is_binary(token) and token != "" do
      raise "Notion token missing (campaign OAuth required)"
    end

    Req.new(
      base_url: @base_url,
      receive_timeout: 15_000,
      pool_timeout: 10_000,
      connect_options: [timeout: 10_000],
      headers: [
        {"Authorization", "Bearer #{token}"},
        {"Notion-Version", @notion_version},
        {"Content-Type", "application/json"}
      ]
    )
  end

  def search(query, opts \\ %{}) do
    opts = normalize_opts(opts)
    {token, opts} = Map.pop(opts, :token)
    body = Map.merge(%{"query" => query}, opts)

    with :ok <- require_token(token) do
      client(token)
      |> Req.post!(url: "/search", json: body)
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def data_source_query(data_source_id, opts \\ %{}) do
    opts = normalize_opts(opts)
    {token, opts} = Map.pop(opts, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.post!(url: "/data_sources/#{data_source_id}/query", json: opts)
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def database_query(database_id, opts \\ %{}) do
    opts = normalize_opts(opts)
    {token, opts} = Map.pop(opts, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.post!(url: "/databases/#{database_id}/query", json: opts)
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def create_page(params) do
    params = normalize_opts(params)
    {token, params} = Map.pop(params, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.post!(url: "/pages", json: params)
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def update_page(page_id, properties, opts \\ %{}) do
    opts = normalize_opts(opts)
    token = Map.get(opts, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.patch!(url: "/pages/#{page_id}", json: %{"properties" => properties})
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def get_page(page_id, opts \\ %{}) do
    opts = normalize_opts(opts)
    token = Map.get(opts, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.get!(url: "/pages/#{page_id}")
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def get_database(database_id, opts \\ %{}) do
    opts = normalize_opts(opts)
    token = Map.get(opts, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.get!(url: "/databases/#{database_id}")
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def get_block_children(block_id, opts \\ %{}) do
    opts = normalize_opts(opts)
    token = Map.get(opts, :token)

    # Build query params for pagination (start_cursor, page_size)
    query_params =
      opts
      |> Map.drop([:token])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    with :ok <- require_token(token) do
      client(token)
      |> Req.get!(url: "/blocks/#{block_id}/children", params: query_params)
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  def append_block_children(block_id, children, opts \\ %{}) do
    opts = normalize_opts(opts)
    token = Map.get(opts, :token)

    with :ok <- require_token(token) do
      client(token)
      |> Req.patch!(url: "/blocks/#{block_id}/children", json: %{"children" => children})
      |> Map.get(:body)
    else
      {:error, err} -> err
    end
  end

  @doc """
  Fetches details about the authenticated Notion integration/bot user.

  Accepts an optional `:token` override in opts to target a specific workspace.
  Returns the response body from Notion's `/users/me` endpoint.
  """
  def get_me(opts \\ %{}) do
    opts = normalize_opts(opts)
    token = Map.get(opts, :token)

    client(token)
    |> Req.get!(url: "/users/me")
    |> Map.get(:body)
  end
end
