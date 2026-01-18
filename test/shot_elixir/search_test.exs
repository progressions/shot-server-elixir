defmodule ShotElixir.SearchTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Search
  alias ShotElixir.{Accounts, Campaigns, Characters, Vehicles, Sites, Factions}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "search-test@example.com",
        password: "password123",
        first_name: "Search",
        last_name: "Test",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Search Test Campaign",
        description: "For search testing",
        user_id: user.id
      })

    %{campaign: campaign, user: user}
  end

  describe "search_all/2" do
    test "returns empty map for empty query", %{campaign: campaign} do
      assert Search.search_all(campaign.id, "") == %{}
    end

    test "returns empty map for nil query", %{campaign: campaign} do
      assert Search.search_all(campaign.id, nil) == %{}
    end

    test "searches characters by name", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "Johnny")

      assert %{"characters" => characters} = results
      assert length(characters) == 1
      assert hd(characters).name == "Johnny Tango"
    end

    test "searches characters by jsonb description", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Generic Name",
          campaign_id: campaign.id,
          character_type: :pc,
          description: %{"description" => "A kung fu master from Hong Kong"}
        })

      results = Search.search_all(campaign.id, "kung fu")

      assert %{"characters" => characters} = results
      assert length(characters) == 1
    end

    test "searches vehicles by name", %{campaign: campaign} do
      {:ok, _} =
        Vehicles.create_vehicle(%{
          name: "Red Porsche",
          campaign_id: campaign.id,
          action_values: %{"Type" => "Car"}
        })

      results = Search.search_all(campaign.id, "Porsche")

      assert %{"vehicles" => vehicles} = results
      assert length(vehicles) == 1
      assert hd(vehicles).name == "Red Porsche"
    end

    test "searches vehicles by jsonb description", %{campaign: campaign} do
      {:ok, _} =
        Vehicles.create_vehicle(%{
          name: "Mystery Car",
          campaign_id: campaign.id,
          action_values: %{"Type" => "Car"},
          description: %{"description" => "A sleek sports car"}
        })

      results = Search.search_all(campaign.id, "sleek sports")

      assert %{"vehicles" => vehicles} = results
      assert length(vehicles) == 1
    end

    test "searches sites by name and description", %{campaign: campaign} do
      {:ok, _} =
        Sites.create_site(%{
          name: "Dragon Palace",
          description: "An ancient feng shui site",
          campaign_id: campaign.id
        })

      # Search by name
      results = Search.search_all(campaign.id, "Dragon")
      assert %{"sites" => sites} = results
      assert length(sites) == 1

      # Search by description
      results = Search.search_all(campaign.id, "feng shui")
      assert %{"sites" => sites} = results
      assert length(sites) == 1
    end

    test "searches factions by name", %{campaign: campaign} do
      {:ok, _} =
        Factions.create_faction(%{
          name: "The Ascended",
          description: "Transformed animals",
          campaign_id: campaign.id
        })

      results = Search.search_all(campaign.id, "Ascended")

      assert %{"factions" => factions} = results
      assert length(factions) == 1
    end

    test "search is case-insensitive", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "johnny")

      assert %{"characters" => characters} = results
      assert length(characters) == 1
    end

    test "search performs partial matching", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "ang")

      assert %{"characters" => characters} = results
      assert length(characters) == 1
    end

    test "results are scoped to campaign", %{campaign: campaign, user: user} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "Different campaign",
          user_id: user.id
        })

      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: other_campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "Test")

      assert %{"characters" => characters} = results
      assert length(characters) == 1
    end

    test "limits results to 5 per entity type", %{campaign: campaign} do
      for i <- 1..7 do
        {:ok, _} =
          Characters.create_character(%{
            name: "Character #{i}",
            campaign_id: campaign.id,
            character_type: :pc
          })
      end

      results = Search.search_all(campaign.id, "Character")

      assert %{"characters" => characters} = results
      assert length(characters) == 5
    end

    test "filters out empty result groups", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "Test")

      # Should only have characters key, not empty keys for other types
      assert Map.keys(results) == ["characters"]
    end

    test "returns multiple entity types when matching", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Entity",
          campaign_id: campaign.id,
          character_type: :pc
        })

      {:ok, _} =
        Sites.create_site(%{
          name: "Test Site",
          description: "A test site",
          campaign_id: campaign.id
        })

      results = Search.search_all(campaign.id, "Test")

      assert Map.has_key?(results, "characters")
      assert Map.has_key?(results, "sites")
    end

    test "result format includes expected fields", %{campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "Test")

      [result | _] = results["characters"]
      assert result.id == character.id
      assert result.name == "Test Character"
      assert result.entity_class == "Character"
      assert Map.has_key?(result, :image_url)
      assert Map.has_key?(result, :description)
    end

    test "image_url is nil in search results", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      results = Search.search_all(campaign.id, "Test")

      [result | _] = results["characters"]
      assert is_nil(result.image_url)
    end
  end
end
