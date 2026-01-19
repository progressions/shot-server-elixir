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

  @apostrophe_pattern ~r/[''ʼ`´]/

  # Normalize search terms for more lenient matching:
  # - Strip common prefixes like "The ", "A ", "An "
  # - Handle apostrophes: Notion may use curly ' vs straight ' which don't match
  #   Since `contains` requires exact substring, we extract the longest word without apostrophes
  #   "Gambler's Journey" -> "Journey" (only word without apostrophe)
  defp normalize_search_term(nil), do: ""
  defp normalize_search_term(""), do: ""

  defp normalize_search_term(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(~r/^(The|A|An)\s+/i, "")
    |> handle_apostrophes()
  end

  # Handle apostrophe variants (straight ' vs curly ' etc.) by finding the longest
  # word that doesn't contain an apostrophe. This ensures reliable matching regardless
  # of which apostrophe variant Notion uses.
  #
  # Examples:
  #   "Gambler's Journey" -> "Journey" (only word without apostrophe)
  #   "O'Brien's O'Malley's" -> "OBriens" (fallback: strip apostrophes, take longest)
  #   "Regular Name" -> "Regular Name" (no apostrophes, unchanged)
  defp handle_apostrophes(name) do
    # Check if name contains any apostrophe variant
    if String.match?(name, @apostrophe_pattern) do
      words = String.split(name, ~r/\s+/)

      # First, prefer words that have no apostrophes at all
      no_apostrophe_words = Enum.reject(words, &String.match?(&1, @apostrophe_pattern))

      cond do
        no_apostrophe_words != [] ->
          Enum.max_by(no_apostrophe_words, &String.length/1)

        true ->
          # If all words contain apostrophes, strip the apostrophes and take the
          # longest remaining substring, or "" if nothing remains. This avoids
          # returning the original name unchanged, which would keep variant-
          # specific apostrophes and can cause Notion `contains` queries to miss.
          cleaned_words =
            words
            |> Enum.map(&String.replace(&1, @apostrophe_pattern, ""))
            |> Enum.reject(&(&1 == ""))

          Enum.max_by(cleaned_words, &String.length/1, fn -> "" end)
      end
    else
      # No apostrophe, return as-is
      name
    end
  end
end
