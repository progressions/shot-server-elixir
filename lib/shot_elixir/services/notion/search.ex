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
    # Normalize search term by stripping common prefixes like "The "
    normalized_name = normalize_search_term(name)

    filter =
      if normalized_name == "" do
        %{}
      else
        %{
          "filter" => %{
            "property" => "Name",
            "title" => %{"contains" => normalized_name}
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

  # Normalize search terms for more lenient matching:
  # - Strip common prefixes like "The ", "A ", "An "
  # - Handle apostrophes: Notion may use curly ' vs straight ' which don't match
  #   Since `contains` requires exact substring, we extract the longest word
  #   "Gambler's Journey" -> "Gambler" (will match "Gambler's Journey" in Notion)
  defp normalize_search_term(nil), do: ""
  defp normalize_search_term(""), do: ""

  defp normalize_search_term(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(~r/^(The|A|An)\s+/i, "")
    |> handle_apostrophes()
  end

  # Handle apostrophe variants by finding the longest word that doesn't contain
  # an apostrophe. This ensures reliable matching regardless of which apostrophe
  # variant (straight ' vs curly ') Notion uses.
  # "Gambler's Journey" -> "Journey" (7 chars) beats "Gambler" (7 chars), but both work
  defp handle_apostrophes(name) do
    # Check if name contains any apostrophe variant
    if String.match?(name, ~r/[''ʼ`´]/) do
      # Split into words, filter out words with apostrophes, take the longest
      name
      |> String.split(~r/\s+/)
      |> Enum.reject(&String.match?(&1, ~r/[''ʼ`´]/))
      |> Enum.max_by(&String.length/1, fn -> name end)
    else
      # No apostrophe, return as-is
      name
    end
  end
end
