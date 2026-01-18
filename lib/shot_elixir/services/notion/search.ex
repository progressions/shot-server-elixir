defmodule ShotElixir.Services.Notion.Search do
  @moduledoc """
  Search helpers for Notion entities and pages.
  """

  require Logger

  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Services.Notion.Blocks
  alias ShotElixir.Services.Notion.Config
  alias ShotElixir.Services.NotionClient

  def find_page_by_name(name) do
    results =
      NotionClient.search(name, %{
        "filter" => %{"property" => "object", "value" => "page"}
      })

    case results do
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion search error: #{error_code} - #{message}")
        []

      %{"results" => pages} when is_list(pages) ->
        Enum.map(pages, fn page ->
          %{
            "id" => page["id"],
            "title" => Blocks.extract_page_title(page),
            "url" => page["url"]
          }
        end)

      _ ->
        Logger.warning("Unexpected response from Notion search: #{inspect(results)}")
        []
    end
  rescue
    error ->
      Logger.error("Failed to search Notion pages: #{Exception.message(error)}")
      []
  end

  def find_pages_in_database(data_source_id, name, opts \\ []) do
    filter =
      if name == "" do
        %{}
      else
        %{
          "filter" => %{
            "property" => "Name",
            "title" => %{"contains" => name}
          }
        }
      end

    client = Config.client(opts)
    token = Keyword.get(opts, :token)
    query_opts = Map.put(filter, :token, token)
    response = client.data_source_query(data_source_id, query_opts)

    case response do
      %{"code" => error_code, "message" => message} ->
        Logger.error("Notion data_source_query error: #{error_code} - #{message}")
        []

      %{"results" => pages} when is_list(pages) ->
        Enum.map(pages, fn page ->
          %{
            "id" => page["id"],
            "title" => Blocks.extract_page_title(page),
            "url" => page["url"]
          }
        end)

      _ ->
        Logger.warning("Unexpected response from Notion data_source_query: #{inspect(response)}")
        []
    end
  rescue
    error ->
      Logger.error("Failed to query Notion database: #{Exception.message(error)}")
      []
  end

  def find_faction_by_name(campaign, name, opts \\ [])

  def find_faction_by_name(nil, _name, _opts), do: []

  def find_faction_by_name(%Campaign{} = campaign, name, opts) do
    filter = %{
      "and" => [
        %{
          "property" => "Name",
          "rich_text" => %{"equals" => name}
        }
      ]
    }

    with {:ok, database_id} <- Config.get_database_id_for_entity(campaign, "factions"),
         {:ok, data_source_id} <- Config.data_source_id_for(database_id, opts) do
      client = Config.client(opts)
      token = Keyword.get(opts, :token)
      query_opts = Map.put(%{"filter" => filter}, :token, token)
      response = client.data_source_query(data_source_id, query_opts)
      response["results"] || []
    else
      {:error, reason} ->
        Logger.error("Failed to resolve Notion data source for factions: #{inspect(reason)}")
        []
    end
  end
end
