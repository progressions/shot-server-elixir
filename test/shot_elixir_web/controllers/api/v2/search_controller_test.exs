defmodule ShotElixirWeb.Api.V2.SearchControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Characters, Sites, Factions, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "search-gm@test.com",
        password: "password123",
        first_name: "Search",
        last_name: "Master",
        gamemaster: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Search Test Campaign",
        description: "Campaign for search testing",
        user_id: gamemaster.id
      })

    # Set current campaign for gamemaster
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> authenticate(gamemaster)

    %{
      conn: conn,
      user: gamemaster,
      campaign: campaign
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "returns empty results for empty query", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search?q=")
      response = json_response(conn, 200)
      assert %{"results" => %{}} = response
    end

    test "returns empty results when no q param provided", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/search")
      response = json_response(conn, 200)
      assert %{"results" => %{}} = response
    end

    test "searches characters by name", %{conn: conn, campaign: campaign} do
      {:ok, _character} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      conn = get(conn, ~p"/api/v2/search?q=Johnny")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"characters" => characters} = results
      assert length(characters) == 1
      assert hd(characters)["name"] == "Johnny Tango"
    end

    test "searches sites by name", %{conn: conn, campaign: campaign} do
      {:ok, _site} =
        Sites.create_site(%{
          name: "Dragon Palace",
          description: "A feng shui site",
          campaign_id: campaign.id
        })

      conn = get(conn, ~p"/api/v2/search?q=Dragon")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"sites" => sites} = results
      assert length(sites) == 1
      assert hd(sites)["name"] == "Dragon Palace"
    end

    test "searches factions by name", %{conn: conn, campaign: campaign} do
      {:ok, _faction} =
        Factions.create_faction(%{
          name: "The Ascended",
          description: "Ancient transformed animals",
          campaign_id: campaign.id
        })

      conn = get(conn, ~p"/api/v2/search?q=Ascended")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"factions" => factions} = results
      assert length(factions) == 1
      assert hd(factions)["name"] == "The Ascended"
    end

    test "search is case-insensitive", %{conn: conn, campaign: campaign} do
      {:ok, _character} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      conn = get(conn, ~p"/api/v2/search?q=johnny")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"characters" => characters} = results
      assert length(characters) == 1
    end

    test "search performs partial matching", %{conn: conn, campaign: campaign} do
      {:ok, _character} =
        Characters.create_character(%{
          name: "Johnny Tango",
          campaign_id: campaign.id,
          character_type: :pc
        })

      conn = get(conn, ~p"/api/v2/search?q=ohn")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"characters" => characters} = results
      assert length(characters) == 1
    end

    test "results are scoped to current campaign", %{conn: conn, campaign: campaign, user: user} do
      # Create character in current campaign
      {:ok, _char1} =
        Characters.create_character(%{
          name: "Campaign Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      # Create another campaign with a character
      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "A different campaign",
          user_id: user.id
        })

      {:ok, _char2} =
        Characters.create_character(%{
          name: "Other Campaign Character",
          campaign_id: other_campaign.id,
          character_type: :pc
        })

      conn = get(conn, ~p"/api/v2/search?q=Character")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"characters" => characters} = results
      # Should only find the character in current campaign
      assert length(characters) == 1
      assert hd(characters)["name"] == "Campaign Character"
    end

    test "limits results to 5 per entity type", %{conn: conn, campaign: campaign} do
      # Create 7 characters
      for i <- 1..7 do
        {:ok, _} =
          Characters.create_character(%{
            name: "Test Character #{i}",
            campaign_id: campaign.id,
            character_type: :pc
          })
      end

      conn = get(conn, ~p"/api/v2/search?q=Test")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert %{"characters" => characters} = results
      assert length(characters) == 5
    end

    test "returns results grouped by entity type", %{conn: conn, campaign: campaign} do
      {:ok, _character} =
        Characters.create_character(%{
          name: "Test Entity",
          campaign_id: campaign.id,
          character_type: :pc
        })

      {:ok, _site} =
        Sites.create_site(%{
          name: "Test Entity Site",
          description: "A test site",
          campaign_id: campaign.id
        })

      conn = get(conn, ~p"/api/v2/search?q=Test")
      response = json_response(conn, 200)

      assert %{"results" => results} = response
      assert Map.has_key?(results, "characters")
      assert Map.has_key?(results, "sites")
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      {:ok, _user} = Accounts.update_user(user, %{current_campaign_id: nil})

      conn = get(conn, ~p"/api/v2/search?q=test")
      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end

    test "requires authentication", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get(~p"/api/v2/search?q=test")

      assert json_response(conn, 401)
    end

    test "result items include expected fields", %{conn: conn, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          character_type: :pc
        })

      conn = get(conn, ~p"/api/v2/search?q=Test")
      response = json_response(conn, 200)

      [result | _] = response["results"]["characters"]
      assert result["id"] == character.id
      assert result["name"] == "Test Character"
      assert result["entity_class"] == "Character"
      assert Map.has_key?(result, "image_url")
      assert Map.has_key?(result, "description")
    end
  end
end
