defmodule ShotElixirWeb.Api.V2.AdventureControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Adventures, Characters, Fights, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm_adventure@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Adventure Test Campaign",
        description: "Campaign for adventure testing",
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
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all adventures for campaign", %{conn: conn, campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Chicago On Fire",
          campaign_id: campaign.id,
          user_id: user.id,
          description: "A blazing adventure"
        })

      conn = get(conn, ~p"/api/v2/adventures")
      assert %{"adventures" => [returned_adventure]} = json_response(conn, 200)
      assert returned_adventure["id"] == adventure.id
      assert returned_adventure["name"] == "Chicago On Fire"
    end

    test "returns empty list when no adventures", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/adventures")
      assert %{"adventures" => []} = json_response(conn, 200)
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      {:ok, user_without_campaign} = Accounts.update_user(user, %{current_campaign_id: nil})

      conn =
        conn
        |> authenticate(user_without_campaign)
        |> get(~p"/api/v2/adventures")

      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end
  end

  describe "show" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Chicago On Fire",
          campaign_id: campaign.id,
          user_id: user.id,
          description: "A blazing adventure"
        })

      %{adventure: adventure}
    end

    test "returns adventure when found", %{conn: conn, adventure: adventure} do
      conn = get(conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert returned_adventure = json_response(conn, 200)
      assert returned_adventure["id"] == adventure.id
      assert returned_adventure["name"] == "Chicago On Fire"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/adventures/#{Ecto.UUID.generate()}")
      assert %{"error" => "Adventure not found"} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "creates adventure with valid data", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/adventures", %{
          adventure: %{
            name: "New Adventure",
            description: "A new adventure",
            season: 1
          }
        })

      assert adventure = json_response(conn, 201)
      assert adventure["name"] == "New Adventure"
      assert adventure["description"] == "A new adventure"
      assert adventure["season"] == 1
    end

    test "returns errors with invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v2/adventures", %{
          adventure: %{
            description: "Missing name"
          }
        })

      assert %{"errors" => %{"name" => _}} = json_response(conn, 422)
    end
  end

  describe "update" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Original Name",
          campaign_id: campaign.id,
          user_id: user.id
        })

      %{adventure: adventure}
    end

    test "updates adventure with valid data", %{conn: conn, adventure: adventure} do
      conn =
        patch(conn, ~p"/api/v2/adventures/#{adventure.id}", %{
          adventure: %{
            name: "Updated Name",
            description: "Updated description"
          }
        })

      assert updated = json_response(conn, 200)
      assert updated["name"] == "Updated Name"
      assert updated["description"] == "Updated description"
    end
  end

  describe "delete" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Adventure to Delete",
          campaign_id: campaign.id,
          user_id: user.id
        })

      %{adventure: adventure}
    end

    test "deletes adventure", %{conn: conn, adventure: adventure} do
      conn = delete(conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert response(conn, 204)

      conn = get(conn, ~p"/api/v2/adventures/#{adventure.id}")
      assert json_response(conn, 404)
    end
  end

  describe "add_character" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Hero",
          campaign_id: campaign.id
        })

      %{adventure: adventure, character: character}
    end

    test "adds character as hero to adventure", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        post(conn, ~p"/api/v2/adventures/#{adventure.id}/characters", %{
          character_id: character.id
        })

      assert updated = json_response(conn, 200)
      assert character.id in updated["character_ids"]
    end
  end

  describe "remove_character" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Hero",
          campaign_id: campaign.id
        })

      {:ok, adventure} = Adventures.add_character(adventure, character.id)

      %{adventure: adventure, character: character}
    end

    test "removes character from adventure heroes", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        delete(conn, ~p"/api/v2/adventures/#{adventure.id}/characters/#{character.id}")

      assert updated = json_response(conn, 200)
      refute character.id in updated["character_ids"]
    end
  end

  describe "add_villain" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Villain",
          campaign_id: campaign.id
        })

      %{adventure: adventure, character: character}
    end

    test "adds character as villain to adventure", %{
      conn: conn,
      adventure: adventure,
      character: character
    } do
      conn =
        post(conn, ~p"/api/v2/adventures/#{adventure.id}/villains", %{
          character_id: character.id
        })

      assert updated = json_response(conn, 200)
      assert character.id in updated["villain_ids"]
    end
  end

  describe "add_fight" do
    setup %{campaign: campaign, user: user} do
      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Test Adventure",
          campaign_id: campaign.id,
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id
        })

      %{adventure: adventure, fight: fight}
    end

    test "adds fight to adventure", %{
      conn: conn,
      adventure: adventure,
      fight: fight
    } do
      conn =
        post(conn, ~p"/api/v2/adventures/#{adventure.id}/fights", %{
          fight_id: fight.id
        })

      assert updated = json_response(conn, 200)
      assert fight.id in updated["fight_ids"]
    end
  end
end
