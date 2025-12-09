defmodule ShotElixirWeb.Api.V2.JunctureControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Junctures, Accounts}
  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Contemporary",
    description: "The modern world as we know it"
  }

  @update_attrs %{
    name: "Future",
    description: "The sci-fi future of 2056"
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
        name: "Juncture Test Campaign",
        description: "Campaign for juncture testing",
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
    test "lists all junctures for campaign", %{conn: conn, campaign: campaign} do
      assert {:ok, _} =
               Junctures.create_juncture(
                 Map.merge(@create_attrs, %{
                   campaign_id: campaign.id,
                   name: "Contemporary"
                 })
               )

      assert {:ok, _} =
               Junctures.create_juncture(
                 Map.merge(@create_attrs, %{
                   campaign_id: campaign.id,
                   name: "Ancient"
                 })
               )

      conn = get(conn, ~p"/api/v2/junctures")
      response = json_response(conn, 200)

      assert %{"junctures" => junctures} = response
      assert length(junctures) == 2

      juncture_names = Enum.map(junctures, & &1["name"])
      assert "Contemporary" in juncture_names
      assert "Ancient" in juncture_names
    end

    test "returns empty list when no junctures", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/junctures")
      assert %{"junctures" => []} = json_response(conn, 200)
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      # Remove current campaign
      {:ok, _user} = Accounts.update_user(user, %{current_campaign_id: nil})

      conn = get(conn, ~p"/api/v2/junctures")
      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end

    test "requires authentication", %{conn: conn} do
      conn = conn |> delete_req_header("authorization")
      conn = get(conn, ~p"/api/v2/junctures")
      assert json_response(conn, 401)
    end
  end

  describe "show" do
    setup %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{juncture: juncture}
    end

    test "shows juncture when found", %{conn: conn, juncture: juncture} do
      conn = get(conn, ~p"/api/v2/junctures/#{juncture.id}")
      returned_juncture = json_response(conn, 200)

      assert returned_juncture["id"] == juncture.id
      assert returned_juncture["name"] == juncture.name
      assert returned_juncture["description"] == juncture.description
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/junctures/#{Ecto.UUID.generate()}")
      assert %{"error" => "Juncture not found"} = json_response(conn, 404)
    end

    test "requires authentication", %{conn: conn, juncture: juncture} do
      conn = conn |> delete_req_header("authorization")
      conn = get(conn, ~p"/api/v2/junctures/#{juncture.id}")
      assert json_response(conn, 401)
    end
  end

  describe "create" do
    test "creates juncture with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/junctures", juncture: @create_attrs)
      juncture = json_response(conn, 201)

      assert juncture["name"] == @create_attrs.name
      assert juncture["description"] == @create_attrs.description
    end

    test "returns errors with invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/junctures", juncture: @invalid_attrs)
      assert %{"errors" => _} = json_response(conn, 422)
    end

    test "requires authentication", %{conn: conn} do
      conn = conn |> delete_req_header("authorization")
      conn = post(conn, ~p"/api/v2/junctures", juncture: @create_attrs)
      assert json_response(conn, 401)
    end
  end

  describe "update" do
    setup %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{juncture: juncture}
    end

    test "updates juncture with valid data", %{conn: conn, juncture: juncture} do
      conn = patch(conn, ~p"/api/v2/junctures/#{juncture.id}", juncture: @update_attrs)
      updated_juncture = json_response(conn, 200)

      assert updated_juncture["name"] == @update_attrs.name
      assert updated_juncture["description"] == @update_attrs.description
    end

    test "returns errors with invalid data", %{conn: conn, juncture: juncture} do
      conn = patch(conn, ~p"/api/v2/junctures/#{juncture.id}", juncture: @invalid_attrs)
      assert %{"errors" => _} = json_response(conn, 422)
    end

    test "returns 404 when juncture not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v2/junctures/#{Ecto.UUID.generate()}", juncture: @update_attrs)
      assert %{"error" => "Juncture not found"} = json_response(conn, 404)
    end

    test "requires authentication", %{conn: conn, juncture: juncture} do
      conn = conn |> delete_req_header("authorization")
      conn = patch(conn, ~p"/api/v2/junctures/#{juncture.id}", juncture: @update_attrs)
      assert json_response(conn, 401)
    end
  end

  describe "delete" do
    setup %{campaign: campaign} do
      {:ok, juncture} =
        Junctures.create_juncture(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{juncture: juncture}
    end

    test "soft deletes juncture (sets active to false)", %{conn: conn, juncture: juncture} do
      conn = delete(conn, ~p"/api/v2/junctures/#{juncture.id}")
      assert response(conn, 204)

      # Verify juncture still exists but is inactive
      updated_juncture = Junctures.get_juncture(juncture.id)
      assert updated_juncture.active == false
    end

    test "returns 404 when juncture not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/junctures/#{Ecto.UUID.generate()}")
      assert %{"error" => "Juncture not found"} = json_response(conn, 404)
    end

    test "requires authentication", %{conn: conn, juncture: juncture} do
      conn = conn |> delete_req_header("authorization")
      conn = delete(conn, ~p"/api/v2/junctures/#{juncture.id}")
      assert json_response(conn, 401)
    end
  end
end
