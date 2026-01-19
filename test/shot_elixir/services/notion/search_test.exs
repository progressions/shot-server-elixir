defmodule ShotElixir.Services.Notion.SearchTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Services.Notion.Search

  # Mock client that echoes back the search term as the title
  # This lets us verify what normalization was applied
  defmodule EchoClient do
    def data_source_query(_data_source_id, opts) do
      filter = Map.get(opts, "filter", %{})
      search_term = get_in(filter, ["title", "contains"]) || "__EMPTY__"

      %{
        "results" => [
          %{
            "id" => "test-page",
            "properties" => %{
              "Name" => %{"title" => [%{"plain_text" => search_term}]}
            },
            "url" => "https://notion.example/test"
          }
        ]
      }
    end
  end

  describe "normalize_search_term via find_pages_in_database" do
    # Helper to extract the normalized search term
    # The mock echoes the search term back as the title
    defp get_normalized_term(name) do
      [result] = Search.find_pages_in_database("test-ds", name, client: EchoClient)
      result["title"]
    end

    test "passes through regular names unchanged" do
      assert get_normalized_term("Regular Name") == "Regular Name"
    end

    test "strips 'The' prefix" do
      assert get_normalized_term("The Guiding Hand") == "Guiding Hand"
    end

    test "strips 'A' prefix" do
      assert get_normalized_term("A Dark Night") == "Dark Night"
    end

    test "strips 'An' prefix" do
      assert get_normalized_term("An Ancient Evil") == "Ancient Evil"
    end

    test "handles name with straight apostrophe - extracts word without apostrophe" do
      # "Gambler's Journey" -> "Journey" (only word without apostrophe)
      assert get_normalized_term("Gambler's Journey") == "Journey"
    end

    test "handles name with curly apostrophe - extracts word without apostrophe" do
      # "Gambler's Journey" with curly apostrophe -> "Journey"
      assert get_normalized_term("Gambler's Journey") == "Journey"
    end

    test "handles multiple words with one having apostrophe" do
      # "John's Big Adventure" -> "Adventure" (longest word without apostrophe)
      assert get_normalized_term("John's Big Adventure") == "Adventure"
    end

    test "handles all words containing apostrophes - strips apostrophes" do
      # "O'Brien's O'Malley's" -> "OMalleys" (stripped, longest)
      assert get_normalized_term("O'Brien's O'Malley's") == "OMalleys"
    end

    test "handles single word with apostrophe - strips apostrophe" do
      # "O'Brien" -> "OBrien"
      assert get_normalized_term("O'Brien") == "OBrien"
    end

    test "handles modifier letter apostrophe" do
      # "Testʼs Value" -> "Value"
      assert get_normalized_term("Testʼs Value") == "Value"
    end

    test "handles grave accent as apostrophe" do
      # "Test`s Value" -> "Value"
      assert get_normalized_term("Test`s Value") == "Value"
    end

    test "handles acute accent as apostrophe" do
      # "Test´s Value" -> "Value"
      assert get_normalized_term("Test´s Value") == "Value"
    end

    test "returns empty marker for nil (no filter applied)" do
      assert get_normalized_term(nil) == "__EMPTY__"
    end

    test "returns empty marker for empty string (no filter applied)" do
      assert get_normalized_term("") == "__EMPTY__"
    end

    test "combines prefix stripping with apostrophe handling" do
      # "The Dragon's Lair" -> strips "The", then extracts "Lair"
      assert get_normalized_term("The Dragon's Lair") == "Lair"
    end

    test "selects longest word when multiple words have no apostrophe" do
      # "Sam's Great Adventure" -> "Adventure" (longest of "Great", "Adventure")
      assert get_normalized_term("Sam's Great Adventure") == "Adventure"
    end
  end
end
