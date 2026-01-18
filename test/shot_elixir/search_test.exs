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

  describe "search_campaign/3" do
    test "returns empty results for empty query", %{campaign: campaign} do
      result = Search.search_campaign(campaign.id, "")

      assert %{results: %{}, meta: meta} = result
      assert meta.query == ""
      assert meta.total_count == 0
    end

    test "returns empty results for nil query", %{campaign: campaign} do
      result = Search.search_campaign(campaign.id, nil)

      assert %{results: %{}, meta: meta} = result
      assert meta.total_count == 0
    end

    test "searches characters by name", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "Johnny")

      assert %{results: results, meta: meta} = result
      assert %{characters: characters} = results
      assert length(characters) == 1
      assert hd(characters).name == "Johnny Tango"
      assert meta.query == "Johnny"
      assert meta.total_count == 1
    end

    test "searches characters by jsonb description", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Generic Name",
          campaign_id: campaign.id,
          character_type: :pc,
          description: %{"description" => "A kung fu master from Hong Kong"}
        })

      result = Search.search_campaign(campaign.id, "kung fu")

      assert %{results: results} = result
      assert %{characters: characters} = results
      assert length(characters) == 1
    end

    test "searches vehicles by name", %{campaign: campaign} do
      {:ok, _} =
        Vehicles.create_vehicle(%{
          name: "Red Porsche",
          campaign_id: campaign.id,
          action_values: %{"Type" => "Car"}
        })

      result = Search.search_campaign(campaign.id, "Porsche")

      assert %{results: results} = result
      assert %{vehicles: vehicles} = results
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

      result = Search.search_campaign(campaign.id, "sleek sports")

      assert %{results: results} = result
      assert %{vehicles: vehicles} = results
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
      result = Search.search_campaign(campaign.id, "Dragon")
      assert %{results: %{sites: sites}} = result
      assert length(sites) == 1

      # Search by description
      result = Search.search_campaign(campaign.id, "feng shui")
      assert %{results: %{sites: sites}} = result
      assert length(sites) == 1
    end

    test "searches factions by name", %{campaign: campaign} do
      {:ok, _} =
        Factions.create_faction(%{
          name: "The Ascended",
          description: "Transformed animals",
          campaign_id: campaign.id
        })

      result = Search.search_campaign(campaign.id, "Ascended")

      assert %{results: %{factions: factions}} = result
      assert length(factions) == 1
    end

    test "search is case-insensitive", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "johnny")

      assert %{results: %{characters: characters}} = result
      assert length(characters) == 1
    end

    test "search performs partial matching", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "ang")

      assert %{results: %{characters: characters}} = result
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

      result = Search.search_campaign(campaign.id, "Test")

      assert %{results: %{characters: characters}} = result
      assert length(characters) == 1
    end

    test "limits results to 5 per entity type by default", %{campaign: campaign} do
      for i <- 1..7 do
        {:ok, _} =
          Characters.create_character(%{
            name: "Character #{i}",
            campaign_id: campaign.id,
            character_type: :pc
          })
      end

      result = Search.search_campaign(campaign.id, "Character")

      assert %{results: %{characters: characters}, meta: meta} = result
      assert length(characters) == 5
      assert meta.limit_per_type == 5
    end

    test "respects custom limit option", %{campaign: campaign} do
      for i <- 1..5 do
        {:ok, _} =
          Characters.create_character(%{
            name: "Character #{i}",
            campaign_id: campaign.id,
            character_type: :pc
          })
      end

      result = Search.search_campaign(campaign.id, "Character", limit: 3)

      assert %{results: %{characters: characters}, meta: meta} = result
      assert length(characters) == 3
      assert meta.limit_per_type == 3
    end

    test "filters out empty result groups", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "Test")

      # Should only have characters key, not empty keys for other types
      assert Map.keys(result.results) == [:characters]
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

      result = Search.search_campaign(campaign.id, "Test")

      assert Map.has_key?(result.results, :characters)
      assert Map.has_key?(result.results, :sites)
      assert result.meta.total_count == 2
    end

    test "result format includes expected fields", %{campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "Test")

      [item | _] = result.results[:characters]
      # Search returns full entity structs
      assert item.__struct__ == ShotElixir.Characters.Character
      assert item.id == character.id
      assert item.name == "Test Character"
      assert Map.has_key?(item, :image_url)
      assert Map.has_key?(item, :description)
    end

    test "image_url is nil in search results", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "Test")

      [item | _] = result.results[:characters]
      assert is_nil(item.image_url)
    end

    test "meta includes query and counts", %{campaign: campaign} do
      {:ok, _} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      result = Search.search_campaign(campaign.id, "Test")

      assert result.meta.query == "Test"
      assert result.meta.limit_per_type == 5
      assert result.meta.total_count == 1
    end
  end
end
