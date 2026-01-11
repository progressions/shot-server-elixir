defmodule ShotElixirWeb.Api.V2.FactionControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Factions, Accounts, Characters}
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Faction",
    description: "A test faction for the campaign"
  }

  @update_attrs %{
    name: "Updated Faction",
    description: "Updated description"
  }

  @invalid_attrs %{name: nil, description: nil}

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Faction Test Campaign",
        description: "Campaign for faction testing",
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
    test "lists all factions for campaign", %{conn: conn, campaign: campaign} do
      assert {:ok, _} =
               Factions.create_faction(
                 Map.merge(@create_attrs, %{
                   campaign_id: campaign.id,
                   name: "Faction 1"
                 })
               )

      assert {:ok, _} =
               Factions.create_faction(
                 Map.merge(@create_attrs, %{
                   campaign_id: campaign.id,
                   name: "Faction 2"
                 })
               )

      conn = get(conn, ~p"/api/v2/factions")
      response = json_response(conn, 200)

      assert %{"factions" => factions} = response
      assert length(factions) == 2

      faction_names = Enum.map(factions, & &1["name"])
      assert "Faction 1" in faction_names
      assert "Faction 2" in faction_names
    end

    test "returns empty list when no factions", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/factions")
      assert %{"factions" => []} = json_response(conn, 200)
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      # Remove current campaign
      {:ok, _user} = Accounts.update_user(user, %{current_campaign_id: nil})

      conn = get(conn, ~p"/api/v2/factions")
      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end

    test "requires authentication", %{conn: conn} do
      conn = conn |> delete_req_header("authorization")
      conn = get(conn, ~p"/api/v2/factions")
      assert json_response(conn, 401)
    end
  end

  describe "show" do
    setup %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{faction: faction}
    end

    test "shows faction when found", %{conn: conn, faction: faction} do
      conn = get(conn, ~p"/api/v2/factions/#{faction.id}")
      returned_faction = json_response(conn, 200)

      assert returned_faction["id"] == faction.id
      assert returned_faction["name"] == faction.name
      assert returned_faction["description"] == faction.description
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/factions/#{Ecto.UUID.generate()}")
      assert %{"error" => "Faction not found"} = json_response(conn, 404)
    end

    test "requires authentication", %{conn: conn, faction: faction} do
      conn = conn |> delete_req_header("authorization")
      conn = get(conn, ~p"/api/v2/factions/#{faction.id}")
      assert json_response(conn, 401)
    end

    test "renders characters (members) association when faction has characters", %{
      conn: conn,
      campaign: campaign,
      user: user
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Faction with Members",
          description: "A faction with characters",
          campaign_id: campaign.id
        })

      {:ok, _character1} =
        Characters.create_character(%{
          name: "Member One",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, _character2} =
        Characters.create_character(%{
          name: "Member Two",
          campaign_id: campaign.id,
          user_id: user.id,
          faction_id: faction.id,
          action_values: %{"Type" => "NPC"}
        })

      conn = get(conn, ~p"/api/v2/factions/#{faction.id}")
      response = json_response(conn, 200)

      assert response["characters"] != nil
      assert is_list(response["characters"])
      assert length(response["characters"]) == 2

      character_names = Enum.map(response["characters"], & &1["name"])
      assert "Member One" in character_names
      assert "Member Two" in character_names
    end

    test "renders empty characters array when faction has no characters", %{
      conn: conn,
      campaign: campaign
    } do
      {:ok, faction} =
        Factions.create_faction(%{
          name: "Empty Faction",
          description: "A faction with no characters",
          campaign_id: campaign.id
        })

      conn = get(conn, ~p"/api/v2/factions/#{faction.id}")
      response = json_response(conn, 200)

      assert response["characters"] == []
    end
  end

  describe "create" do
    test "creates faction with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/factions", faction: @create_attrs)
      faction = json_response(conn, 201)

      assert faction["name"] == @create_attrs.name
      assert faction["description"] == @create_attrs.description
    end

    test "returns errors with invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/factions", faction: @invalid_attrs)
      assert %{"errors" => _} = json_response(conn, 422)
    end

    test "requires authentication", %{conn: conn} do
      conn = conn |> delete_req_header("authorization")
      conn = post(conn, ~p"/api/v2/factions", faction: @create_attrs)
      assert json_response(conn, 401)
    end
  end

  describe "update" do
    setup %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{faction: faction}
    end

    test "updates faction with valid data", %{conn: conn, faction: faction} do
      conn = patch(conn, ~p"/api/v2/factions/#{faction.id}", faction: @update_attrs)
      updated_faction = json_response(conn, 200)

      assert updated_faction["name"] == @update_attrs.name
      assert updated_faction["description"] == @update_attrs.description
    end

    test "returns errors with invalid data", %{conn: conn, faction: faction} do
      conn = patch(conn, ~p"/api/v2/factions/#{faction.id}", faction: @invalid_attrs)
      assert %{"errors" => _} = json_response(conn, 422)
    end

    test "returns 404 when faction not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v2/factions/#{Ecto.UUID.generate()}", faction: @update_attrs)
      assert %{"error" => "Faction not found"} = json_response(conn, 404)
    end

    test "requires authentication", %{conn: conn, faction: faction} do
      conn = conn |> delete_req_header("authorization")
      conn = patch(conn, ~p"/api/v2/factions/#{faction.id}", faction: @update_attrs)
      assert json_response(conn, 401)
    end
  end

  describe "delete" do
    setup %{campaign: campaign} do
      {:ok, faction} =
        Factions.create_faction(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{faction: faction}
    end

    test "hard deletes faction", %{conn: conn, faction: faction} do
      conn = delete(conn, ~p"/api/v2/factions/#{faction.id}")
      assert response(conn, 204)

      # Verify faction is completely removed from database
      assert Factions.get_faction(faction.id) == nil
    end

    test "returns 404 when faction not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/factions/#{Ecto.UUID.generate()}")
      assert %{"error" => "Faction not found"} = json_response(conn, 404)
    end

    test "requires authentication", %{conn: conn, faction: faction} do
      conn = conn |> delete_req_header("authorization")
      conn = delete(conn, ~p"/api/v2/factions/#{faction.id}")
      assert json_response(conn, 401)
    end
  end
end
