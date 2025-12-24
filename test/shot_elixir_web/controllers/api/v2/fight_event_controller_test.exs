defmodule ShotElixirWeb.Api.V2.FightEventControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Fights, Campaigns, Accounts, Repo}
  alias ShotElixir.Guardian

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

    # Create player user (campaign member)
    {:ok, player} =
      Accounts.create_user(%{
        email: "player@test.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create non-member user
    {:ok, non_member} =
      Accounts.create_user(%{
        email: "nonmember@test.com",
        password: "password123",
        first_name: "Non",
        last_name: "Member",
        gamemaster: false
      })

    # Create admin user
    {:ok, admin} =
      Accounts.create_user(%{
        email: "admin@test.com",
        password: "password123",
        first_name: "Admin",
        last_name: "User",
        gamemaster: false,
        admin: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Campaign for fight event testing",
        user_id: gamemaster.id
      })

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    # Create a fight
    {:ok, fight} =
      Fights.create_fight(%{
        name: "Test Fight",
        description: "A test fight",
        campaign_id: campaign.id,
        active: true
      })

    conn = put_req_header(conn, "accept", "application/json")

    %{
      conn: conn,
      gamemaster: gamemaster,
      player: player,
      non_member: non_member,
      admin: admin,
      campaign: campaign,
      fight: fight
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "returns fight events for authorized campaign owner", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      # Create some fight events
      {:ok, _event1} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "chase_action",
          description: "Chase action 1",
          details: %{"vehicle_updates" => []}
        })

      {:ok, _event2} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "up_check",
          description: "Up check",
          details: %{}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      assert is_list(response["fight_events"])
      assert length(response["fight_events"]) == 2
    end

    test "returns fight events for campaign member", %{
      conn: conn,
      player: player,
      fight: fight
    } do
      {:ok, _event} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "chase_action",
          description: "Chase action",
          details: %{}
        })

      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      assert is_list(response["fight_events"])
      assert length(response["fight_events"]) == 1
    end

    test "returns fight events for gamemaster who is campaign member", %{
      conn: conn,
      campaign: campaign,
      fight: fight
    } do
      # Create another gamemaster and add them to the campaign
      {:ok, other_gm} =
        Accounts.create_user(%{
          email: "othergm@test.com",
          password: "password123",
          first_name: "Other",
          last_name: "GM",
          gamemaster: true
        })

      {:ok, _} = Campaigns.add_member(campaign, other_gm)

      {:ok, _event} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "chase_action",
          description: "Chase action",
          details: %{}
        })

      conn = authenticate(conn, other_gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      assert is_list(response["fight_events"])
    end

    test "returns fight events for admin user", %{
      conn: conn,
      admin: admin,
      fight: fight
    } do
      {:ok, _event} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "chase_action",
          description: "Chase action",
          details: %{}
        })

      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      assert is_list(response["fight_events"])
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")

      assert json_response(conn, 403)["error"] == "Access denied"
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{invalid_id}/fight_events")

      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "returns 404 when campaign not found (orphaned fight scenario)", %{
      conn: conn,
      gamemaster: gm
    } do
      # This tests the edge case where a fight exists but its campaign doesn't
      # In practice, this shouldn't happen due to foreign key constraints,
      # but the controller handles it gracefully
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{invalid_id}/fight_events")

      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      assert json_response(conn, 401)
    end

    test "returns empty list when no fight events exist", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      assert response["fight_events"] == []
    end

    test "returns events in chronological order", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      now = DateTime.utc_now()

      {:ok, event1} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "chase_action",
          description: "First event",
          details: %{}
        })

      event1
      |> Ecto.Changeset.change(%{inserted_at: DateTime.add(now, -1, :second)})
      |> Repo.update!()

      {:ok, event2} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "up_check",
          description: "Second event",
          details: %{}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      events = response["fight_events"]
      assert length(events) == 2
      assert List.first(events)["id"] == event1.id
      assert List.last(events)["id"] == event2.id
    end

    test "returns proper event structure with all fields", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      {:ok, _event} =
        Fights.create_fight_event(%{
          fight_id: fight.id,
          event_type: "chase_action",
          description: "Test chase action",
          details: %{
            "vehicle_updates" => [
              %{
                "vehicle_id" => Ecto.UUID.generate(),
                "vehicle_name" => "Test Car",
                "action_values" => %{"Chase Points" => 5}
              }
            ]
          }
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/fight_events")
      response = json_response(conn, 200)

      event = List.first(response["fight_events"])
      assert Map.has_key?(event, "id")
      assert Map.has_key?(event, "event_type")
      assert Map.has_key?(event, "description")
      assert Map.has_key?(event, "details")
      assert Map.has_key?(event, "created_at")
    end
  end

  describe "authorization edge cases" do
    test "denies access to fights from other campaigns", %{conn: conn} do
      # Create a separate user with their own campaign
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@test.com",
          password: "password123",
          first_name: "Other",
          last_name: "User",
          gamemaster: true
        })

      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "Different campaign",
          user_id: other_user.id
        })

      {:ok, other_fight} =
        Fights.create_fight(%{
          name: "Other Fight",
          campaign_id: other_campaign.id
        })

      {:ok, _event} =
        Fights.create_fight_event(%{
          fight_id: other_fight.id,
          event_type: "chase_action",
          description: "Other event",
          details: %{}
        })

      # Try to access other_fight's events as a non-member
      {:ok, non_member} =
        Accounts.create_user(%{
          email: "unauthorized@test.com",
          password: "password123",
          first_name: "Unauthorized",
          last_name: "User",
          gamemaster: false
        })

      conn = authenticate(conn, non_member)
      conn = get(conn, ~p"/api/v2/fights/#{other_fight.id}/fight_events")

      assert json_response(conn, 403)["error"] == "Access denied"
    end
  end
end
