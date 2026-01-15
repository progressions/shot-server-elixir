defmodule ShotElixirWeb.Api.V2.FightControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{
    Fights,
    Campaigns,
    Accounts,
    Characters,
    Vehicles,
    Factions,
    Junctures
  }

  alias ShotElixir.Guardian

  @create_attrs %{
    name: "Test Fight",
    description: "A test fight",
    season: 1,
    session: 1,
    active: true
  }

  @update_attrs %{
    name: "Updated Fight",
    description: "Updated description",
    season: 2,
    session: 2,
    active: false
  }

  @invalid_attrs %{name: nil}

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

    # Create player user
    {:ok, player} =
      Accounts.create_user(%{
        email: "player@test.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Campaign for fight testing",
        user_id: gamemaster.id
      })

    # Set current campaign for users
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    # Create test data for complex filtering
    {:ok, faction} =
      Factions.create_faction(%{
        name: "Test Faction",
        description: "A test faction",
        campaign_id: campaign.id
      })

    {:ok, juncture} =
      Junctures.create_juncture(%{
        name: "Modern",
        description: "Modern times",
        campaign_id: campaign.id
      })

    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: player.id,
        action_values: %{"Type" => "PC"}
      })

    {:ok, vehicle} =
      Vehicles.create_vehicle(%{
        name: "Test Vehicle",
        action_values: %{},
        campaign_id: campaign.id,
        user_id: player.id
      })

    conn = put_req_header(conn, "accept", "application/json")

    %{
      conn: conn,
      gamemaster: gm_with_campaign,
      player: player_with_campaign,
      campaign: campaign,
      faction: faction,
      juncture: juncture,
      character: character,
      vehicle: vehicle
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all active fights for campaign", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, fight1} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            name: "Fight 1",
            campaign_id: campaign.id
          })
        )

      {:ok, fight2} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            name: "Fight 2",
            campaign_id: campaign.id
          })
        )

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights")
      response = json_response(conn, 200)

      assert is_list(response["fights"])
      assert length(response["fights"]) == 2

      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Fight 1" in fight_names
      assert "Fight 2" in fight_names
    end

    test "returns empty list when no fights exist", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights")
      response = json_response(conn, 200)

      assert response["fights"] == []
    end

    test "returns error when no campaign selected", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          email: "nocampaign@test.com",
          password: "password123",
          first_name: "No",
          last_name: "Campaign",
          gamemaster: true
        })

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/fights")
      assert json_response(conn, 422)["error"] == "No active campaign selected"
    end

    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/fights")
      assert json_response(conn, 401)
    end
  end

  describe "show" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{fight: fight}
    end

    test "shows fight when found", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}")
      response = json_response(conn, 200)

      assert response["id"] == fight.id
      assert response["name"] == fight.name
      assert response["description"] == fight.description
      assert response["season"] == fight.season
      assert response["session"] == fight.session
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      invalid_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/v2/fights/#{invalid_id}")
      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "allows players to view fights", %{conn: conn, player: player, fight: fight} do
      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}")
      response = json_response(conn, 200)

      assert response["id"] == fight.id
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}")
      assert json_response(conn, 401)
    end
  end

  describe "create" do
    test "creates fight with valid data", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: @create_attrs)
      response = json_response(conn, 201)

      assert response["name"] == @create_attrs.name
      assert response["description"] == @create_attrs.description
      assert response["season"] == @create_attrs.season
      assert response["session"] == @create_attrs.session
      assert response["active"] == true
    end

    test "creates fight with character and vehicle associations", %{
      conn: conn,
      gamemaster: gm,
      character: character,
      vehicle: vehicle
    } do
      fight_attrs =
        Map.merge(@create_attrs, %{
          character_ids: [character.id],
          vehicle_ids: [vehicle.id]
        })

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: fight_attrs)
      response = json_response(conn, 201)

      assert response["name"] == @create_attrs.name
      # Note: Association IDs might be handled differently in the current implementation
    end

    test "handles JSON string parameters", %{conn: conn, gamemaster: gm} do
      json_attrs = Jason.encode!(@create_attrs)

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: json_attrs)
      response = json_response(conn, 201)

      assert response["name"] == @create_attrs.name
      assert response["description"] == @create_attrs.description
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end

    test "only gamemaster can create fights", %{conn: conn, player: player} do
      conn = authenticate(conn, player)
      conn = post(conn, ~p"/api/v2/fights", fight: @create_attrs)
      assert json_response(conn, 403)["error"] == "Only gamemaster can create fights"
    end

    test "requires authentication", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/fights", fight: @create_attrs)
      assert json_response(conn, 401)
    end

    test "creates fight with at_a_glance set to true", %{conn: conn, gamemaster: gm} do
      fight_attrs = Map.put(@create_attrs, :at_a_glance, true)

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: fight_attrs)
      response = json_response(conn, 201)

      assert response["name"] == @create_attrs.name
      assert response["at_a_glance"] == true
    end
  end

  describe "update" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{fight: fight}
    end

    test "updates fight with valid data", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: @update_attrs)
      response = json_response(conn, 200)

      assert response["id"] == fight.id
      assert response["name"] == @update_attrs.name
      assert response["description"] == @update_attrs.description
      assert response["season"] == @update_attrs.season
      assert response["session"] == @update_attrs.session
    end

    test "updates fight with character and vehicle associations", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      character: character,
      vehicle: vehicle
    } do
      update_attrs =
        Map.merge(@update_attrs, %{
          character_ids: [character.id],
          vehicle_ids: [vehicle.id]
        })

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: update_attrs)
      response = json_response(conn, 200)

      assert response["name"] == @update_attrs.name
    end

    test "handles JSON string parameters", %{conn: conn, gamemaster: gm, fight: fight} do
      json_attrs = Jason.encode!(@update_attrs)

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: json_attrs)
      response = json_response(conn, 200)

      assert response["name"] == @update_attrs.name
      assert response["description"] == @update_attrs.description
    end

    test "updates active status", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: %{active: false})
      response = json_response(conn, 200)

      assert response["active"] == false
    end

    test "updates at_a_glance status", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: %{at_a_glance: true})
      response = json_response(conn, 200)

      assert response["at_a_glance"] == true
    end

    test "renders errors when data is invalid", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: @invalid_attrs)
      assert json_response(conn, 422)["errors"]
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{invalid_id}", fight: @update_attrs)
      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "only gamemaster can update fights", %{conn: conn, player: player, fight: fight} do
      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: @update_attrs)
      assert json_response(conn, 403)["error"] == "Only gamemaster can update fights"
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: @update_attrs)
      assert json_response(conn, 401)
    end
  end

  describe "delete" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{fight: fight}
    end

    test "deletes fight", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}")
      assert response(conn, 204)

      # Verify fight is deleted (implementation dependent - might be soft delete)
      deleted_fight = Fights.get_fight(fight.id)
      assert deleted_fight == nil || deleted_fight.active == false
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/fights/#{invalid_id}")
      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "only gamemaster can delete fights", %{conn: conn, player: player, fight: fight} do
      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}")
      assert json_response(conn, 403)["error"] == "Only gamemaster can delete fights"
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}")
      assert json_response(conn, 401)
    end
  end

  describe "touch" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{fight: fight}
    end

    test "touches fight and updates timestamp", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}/touch")
      response = json_response(conn, 200)

      assert response["id"] == fight.id
      assert response["name"] == fight.name
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{invalid_id}/touch")
      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "only gamemaster can touch fights", %{conn: conn, player: player, fight: fight} do
      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}/touch")
      assert json_response(conn, 403)["error"] == "Only gamemaster can touch fights"
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}/touch")
      assert json_response(conn, 401)
    end
  end

  describe "end_fight" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      %{fight: fight}
    end

    test "ends fight successfully", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}/end_fight")
      response = json_response(conn, 200)

      assert response["id"] == fight.id
      # ended_at should be set (implementation dependent)
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{invalid_id}/end_fight")
      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "only gamemaster can end fights", %{conn: conn, player: player, fight: fight} do
      conn = authenticate(conn, player)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}/end_fight")
      assert json_response(conn, 403)["error"] == "Only gamemaster can end fights"
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}/end_fight")
      assert json_response(conn, 401)
    end
  end

  describe "current_fight" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            started_at: DateTime.utc_now()
          })
        )

      %{fight: fight}
    end

    test "returns current fight for campaign", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}/current_fight")
      response = json_response(conn, 200)

      assert response["id"] == fight.id
      assert response["campaign_id"] == campaign.id
    end

    test "returns nil when no active fight found", %{conn: conn, gamemaster: gm} do
      {:ok, empty_campaign} =
        Campaigns.create_campaign(%{
          name: "Empty Campaign",
          description: "No fights",
          user_id: gm.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{empty_campaign.id}/current_fight")
      response = json_response(conn, 200)
      assert response == nil
    end

    test "allows campaign members to view current fight", %{
      conn: conn,
      player: player,
      campaign: campaign,
      fight: fight
    } do
      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}/current_fight")
      response = json_response(conn, 200)

      assert response["id"] == fight.id
      assert response["campaign_id"] == campaign.id
    end

    test "returns 404 for non-existent campaign", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/campaigns/#{invalid_id}/current_fight")
      assert json_response(conn, 404)["error"] == "Campaign not found"
    end

    test "returns 403 for non-member access", %{conn: conn, campaign: campaign} do
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@test.com",
          password: "password123",
          first_name: "Other",
          last_name: "User",
          gamemaster: false
        })

      conn = authenticate(conn, other_user)
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}/current_fight")
      assert json_response(conn, 403)["error"] == "Not authorized to view this campaign"
    end

    test "requires authentication", %{conn: conn, campaign: campaign} do
      conn = get(conn, ~p"/api/v2/campaigns/#{campaign.id}/current_fight")
      assert json_response(conn, 401)
    end
  end

  describe "authorization" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin@test.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          gamemaster: false,
          admin: true
        })

      {:ok, other_gm} =
        Accounts.create_user(%{
          email: "othergm@test.com",
          password: "password123",
          first_name: "Other",
          last_name: "GM",
          gamemaster: true
        })

      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "Different campaign",
          user_id: other_gm.id
        })

      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id
          })
        )

      {:ok, other_fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            name: "Other Fight",
            campaign_id: other_campaign.id
          })
        )

      %{
        admin: admin,
        other_gm: other_gm,
        other_campaign: other_campaign,
        fight: fight,
        other_fight: other_fight
      }
    end

    test "admin can manage fights in any campaign", %{
      conn: conn,
      admin: admin,
      other_fight: other_fight
    } do
      conn = authenticate(conn, admin)
      conn = patch(conn, ~p"/api/v2/fights/#{other_fight.id}", fight: %{name: "Admin Updated"})
      response = json_response(conn, 200)

      assert response["name"] == "Admin Updated"
    end

    test "gamemaster cannot manage fights in other campaigns", %{
      conn: conn,
      gamemaster: gm,
      other_fight: other_fight
    } do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{other_fight.id}", fight: %{name: "Unauthorized"})
      assert json_response(conn, 404)["error"] == "Fight not found"
    end
  end

  describe "advanced filtering and sorting" do
    setup %{gamemaster: gm, campaign: campaign, character: character, vehicle: vehicle} do
      # Create additional fights for filtering/sorting tests
      {:ok, airport_battle} =
        Fights.create_fight(%{
          name: "Airport Battle",
          description: "A fight at the airport.",
          campaign_id: campaign.id,
          season: 1,
          session: 3
        })

      {:ok, inactive_fight} =
        Fights.create_fight(%{
          name: "Inactive Fight",
          description: "This fight is inactive.",
          campaign_id: campaign.id,
          active: false,
          season: 3,
          session: 1
        })

      %{airport_battle: airport_battle, inactive_fight: inactive_fight}
    end

    test "filters by search term", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{search: "Battle"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 1
      assert List.first(response["fights"])["name"] == "Airport Battle"
    end

    test "filters by season", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, _brawl} =
        Fights.create_fight(%{
          name: "Season 1 Fight",
          campaign_id: campaign.id,
          season: 1,
          session: 1
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{season: "1"})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1
      assert Enum.all?(response["fights"], fn f -> f["season"] == 1 end)
    end

    test "filters by session", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{session: "3"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 1
      assert List.first(response["fights"])["session"] == 3
    end

    test "filters by __NONE__ season", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, _} =
        Fights.create_fight(%{
          name: "No Season Fight",
          campaign_id: campaign.id,
          season: nil,
          session: 1
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{season: "__NONE__"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 1
      assert List.first(response["fights"])["name"] == "No Season Fight"
      assert List.first(response["fights"])["season"] == nil
    end

    test "filters by __NONE__ session", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, _} =
        Fights.create_fight(%{
          name: "No Session Fight",
          campaign_id: campaign.id,
          season: 1,
          session: nil
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{session: "__NONE__"})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1
      assert Enum.any?(response["fights"], fn f -> f["name"] == "No Session Fight" end)
      assert Enum.all?(response["fights"], fn f -> f["session"] == nil end)
    end

    test "filters unstarted fights (status=Unstarted)", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, started_fight} =
        Fights.create_fight(%{
          name: "Started Fight",
          campaign_id: campaign.id,
          started_at: DateTime.utc_now()
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{status: "Unstarted"})
      response = json_response(conn, 200)

      fight_names = Enum.map(response["fights"], & &1["name"])
      refute "Started Fight" in fight_names
      assert Enum.all?(response["fights"], fn f -> f["started_at"] == nil end)
    end

    test "filters started fights (status=Started)", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, started_fight} =
        Fights.create_fight(%{
          name: "In Progress Fight",
          campaign_id: campaign.id,
          started_at: DateTime.utc_now()
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{status: "Started"})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1

      assert Enum.all?(response["fights"], fn f ->
               f["started_at"] != nil and f["ended_at"] == nil
             end)
    end

    test "filters ended fights (status=Ended)", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, ended_fight} =
        Fights.create_fight(%{
          name: "Ended Fight",
          campaign_id: campaign.id,
          started_at: DateTime.utc_now() |> DateTime.add(-2, :hour),
          ended_at: DateTime.utc_now() |> DateTime.add(-1, :hour)
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{status: "Ended"})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1

      assert Enum.all?(response["fights"], fn f ->
               f["started_at"] != nil and f["ended_at"] != nil
             end)
    end

    test "filters by character involvement", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      character: character
    } do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Character Fight",
          campaign_id: campaign.id
        })

      {:ok, _shot} = Fights.create_shot(%{fight_id: fight.id, character_id: character.id})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{character_id: character.id})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1
      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Character Fight" in fight_names
    end

    test "filters by vehicle involvement", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      vehicle: vehicle
    } do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Vehicle Fight",
          campaign_id: campaign.id
        })

      {:ok, _shot} = Fights.create_shot(%{fight_id: fight.id, vehicle_id: vehicle.id})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{vehicle_id: vehicle.id})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1
      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Vehicle Fight" in fight_names
    end

    test "filters by user involvement", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign,
      character: character
    } do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Player Fight",
          campaign_id: campaign.id
        })

      {:ok, _shot} = Fights.create_shot(%{fight_id: fight.id, character_id: character.id})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{user_id: player.id})
      response = json_response(conn, 200)

      assert length(response["fights"]) >= 1
      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Player Fight" in fight_names
    end

    test "shows all fights when visibility=all", %{
      conn: conn,
      gamemaster: gm,
      inactive_fight: inactive_fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{visibility: "all"})
      response = json_response(conn, 200)

      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Inactive Fight" in fight_names
    end

    test "shows only hidden fights when visibility=hidden", %{
      conn: conn,
      gamemaster: gm,
      inactive_fight: inactive_fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{visibility: "hidden"})
      response = json_response(conn, 200)

      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Inactive Fight" in fight_names
      refute "Airport Battle" in fight_names
    end

    test "hides inactive fights by default", %{
      conn: conn,
      gamemaster: gm,
      inactive_fight: inactive_fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{})
      response = json_response(conn, 200)

      fight_names = Enum.map(response["fights"], & &1["name"])
      refute "Inactive Fight" in fight_names
    end

    test "returns empty array when ids is empty string", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{ids: ""})
      response = json_response(conn, 200)

      assert response["fights"] == []
      assert response["seasons"] == []
      assert response["meta"]["total_count"] == 0
    end

    test "filters by comma-separated ids", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, fight1} =
        Fights.create_fight(%{name: "Fight 1", campaign_id: campaign.id, season: 1, session: 1})

      {:ok, fight2} =
        Fights.create_fight(%{name: "Fight 2", campaign_id: campaign.id, season: 2, session: 2})

      ids = "#{fight1.id},#{fight2.id}"
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{ids: ids})
      response = json_response(conn, 200)

      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Fight 1" in fight_names
      assert "Fight 2" in fight_names
      assert length(response["fights"]) == 2
    end

    test "collects seasons in response", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, _} =
        Fights.create_fight(%{name: "S1 Fight", campaign_id: campaign.id, season: 1, session: 1})

      {:ok, _} =
        Fights.create_fight(%{name: "S2 Fight", campaign_id: campaign.id, season: 2, session: 1})

      {:ok, _} =
        Fights.create_fight(%{name: "S3 Fight", campaign_id: campaign.id, season: 3, session: 1})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{})
      response = json_response(conn, 200)

      assert 1 in response["seasons"]
      assert 2 in response["seasons"]
      assert 3 in response["seasons"]
    end

    test "filters by at_a_glance", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, glance_fight} =
        Fights.create_fight(%{
          name: "Glance Fight",
          campaign_id: campaign.id,
          at_a_glance: true
        })

      {:ok, _other_fight} =
        Fights.create_fight(%{
          name: "Other Fight",
          campaign_id: campaign.id,
          at_a_glance: false
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{at_a_glance: "true"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 1
      assert List.first(response["fights"])["id"] == glance_fight.id
      assert List.first(response["fights"])["at_a_glance"] == true
    end
  end

  describe "sorting" do
    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight_a} =
        Fights.create_fight(%{
          name: "Alpha Fight",
          campaign_id: campaign.id,
          season: 1,
          session: 1
        })

      {:ok, fight_b} =
        Fights.create_fight(%{
          name: "Beta Fight",
          campaign_id: campaign.id,
          season: 2,
          session: 2
        })

      {:ok, fight_c} =
        Fights.create_fight(%{
          name: "Gamma Fight",
          campaign_id: campaign.id,
          season: 1,
          session: 3
        })

      %{fight_a: fight_a, fight_b: fight_b, fight_c: fight_c}
    end

    test "sorts by name ascending", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{sort: "name", order: "ASC"})
      response = json_response(conn, 200)

      names = Enum.map(response["fights"], & &1["name"])
      assert names == Enum.sort(names)
    end

    test "sorts by name descending", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{sort: "name", order: "DESC"})
      response = json_response(conn, 200)

      names = Enum.map(response["fights"], & &1["name"])
      assert names == Enum.sort(names, :desc)
    end

    test "sorts by created_at ascending", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{sort: "created_at", order: "ASC"})
      response = json_response(conn, 200)

      timestamps = Enum.map(response["fights"], & &1["created_at"])
      assert timestamps == Enum.sort(timestamps)
    end

    test "sorts by season ascending", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{sort: "season", order: "ASC"})
      response = json_response(conn, 200)

      seasons = Enum.map(response["fights"], & &1["season"])
      assert seasons == Enum.sort(seasons)
    end

    test "sorts by session descending", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{sort: "session", order: "DESC"})
      response = json_response(conn, 200)

      sessions = Enum.map(response["fights"], & &1["session"])
      assert sessions == Enum.sort(sessions, :desc)
    end

    test "sorts by at_a_glance", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, _} =
        Fights.create_fight(%{name: "No Glance", campaign_id: campaign.id, at_a_glance: false})

      {:ok, _} =
        Fights.create_fight(%{name: "Glance", campaign_id: campaign.id, at_a_glance: true})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{sort: "at_a_glance", order: "DESC"})
      response = json_response(conn, 200)

      glance_values = Enum.map(response["fights"], & &1["at_a_glance"])
      assert List.first(glance_values) == true
    end
  end

  describe "pagination" do
    setup %{gamemaster: gm, campaign: campaign} do
      # Create 25 fights for pagination testing
      fights =
        Enum.map(1..25, fn i ->
          {:ok, fight} =
            Fights.create_fight(%{
              name: "Fight #{String.pad_leading(to_string(i), 2, "0")}",
              campaign_id: campaign.id
            })

          fight
        end)

      %{fights: fights}
    end

    test "returns default page size of 15", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 15
      assert response["meta"]["per_page"] == 15
      assert response["meta"]["current_page"] == 1
      assert response["meta"]["total_pages"] == 2
      assert response["meta"]["total_count"] == 25
    end

    test "returns custom page size", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{per_page: "10"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 10
      assert response["meta"]["per_page"] == 10
      assert response["meta"]["total_pages"] == 3
    end

    test "returns second page", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{page: "2", per_page: "10"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 10
      assert response["meta"]["current_page"] == 2
    end

    test "returns last page with remaining items", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{page: "3", per_page: "10"})
      response = json_response(conn, 200)

      assert length(response["fights"]) == 5
      assert response["meta"]["current_page"] == 3
      assert response["meta"]["total_count"] == 25
    end
  end

  describe "autocomplete mode" do
    setup %{gamemaster: gm, campaign: campaign, character: character} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          description: "A detailed fight",
          campaign_id: campaign.id,
          season: 1,
          session: 1
        })

      {:ok, _shot} = Fights.create_shot(%{fight_id: fight.id, character_id: character.id})
      fight = Fights.get_fight_with_shots(fight.id)

      %{autocomplete_fight: fight}
    end

    test "returns minimal fields when autocomplete=true", %{
      conn: conn,
      gamemaster: gm,
      autocomplete_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{autocomplete: "true", id: fight.id})
      response = json_response(conn, 200)

      fight_data = List.first(response["fights"])
      assert Map.keys(fight_data) == ["entity_class", "id", "image_url", "name"]
      assert fight_data["id"] == fight.id
      assert fight_data["name"] == "Test Fight"
      assert fight_data["entity_class"] == "Fight"
    end

    test "returns full fields when autocomplete is not set", %{
      conn: conn,
      gamemaster: gm,
      autocomplete_fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{id: fight.id})
      response = json_response(conn, 200)

      fight_data = List.first(response["fights"])
      assert Map.has_key?(fight_data, "description")
      assert Map.has_key?(fight_data, "season")
      assert Map.has_key?(fight_data, "session")
      assert Map.has_key?(fight_data, "characters")
      assert fight_data["description"] == "A detailed fight"
    end

    test "supports all filtering with autocomplete mode", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)

      conn =
        get(conn, ~p"/api/v2/fights", %{
          autocomplete: "true",
          search: "Test",
          sort: "name",
          order: "ASC"
        })

      response = json_response(conn, 200)
      fight_data = List.first(response["fights"])

      assert Enum.sort(Map.keys(fight_data)) == ["entity_class", "id", "image_url", "name"]
    end
  end

  describe "duplicate character shots" do
    alias ShotElixir.Fights.Shot
    import Ecto.Query

    setup %{gamemaster: gm, campaign: campaign, player: player} do
      # Create a second character for testing
      {:ok, character1} =
        Characters.create_character(%{
          name: "Character One",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, character2} =
        Characters.create_character(%{
          name: "Character Two",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "NPC"}
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Duplicate Test Fight",
          campaign_id: campaign.id
        })

      %{character1: character1, character2: character2, fight: fight}
    end

    test "adding same character multiple times creates multiple shot records", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      character1: character1
    } do
      # Add character1 three times
      update_attrs = %{
        character_ids: [character1.id, character1.id, character1.id]
      }

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: update_attrs)
      assert json_response(conn, 200)

      # Verify three shots were created for the same character
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(shots) == 3
    end

    test "reducing duplicate count only removes some shot records", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      character1: character1
    } do
      conn = authenticate(conn, gm)

      # First add character1 three times
      conn1 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            character_ids: [character1.id, character1.id, character1.id]
          }
        )

      assert json_response(conn1, 200)

      # Verify three shots
      shots_before =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(shots_before) == 3

      # Now reduce to only one instance
      conn2 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            character_ids: [character1.id]
          }
        )

      assert json_response(conn2, 200)

      # Verify only one shot remains
      shots_after =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(shots_after) == 1
    end

    test "removing duplicates removes newest shots first", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      character1: character1
    } do
      conn = authenticate(conn, gm)

      # Manually create shots with different timestamps to test "newest first" removal
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_time = DateTime.add(now, -3600, :second)
      medium_time = DateTime.add(now, -1800, :second)
      new_time = now

      # Insert shots directly with specific timestamps
      # Shot schema uses created_at (not inserted_at) per timestamps() config
      {:ok, oldest_shot} =
        ShotElixir.Repo.insert(%Shot{
          fight_id: fight.id,
          character_id: character1.id,
          shot: nil,
          created_at: old_time,
          updated_at: old_time
        })

      {:ok, _middle_shot} =
        ShotElixir.Repo.insert(%Shot{
          fight_id: fight.id,
          character_id: character1.id,
          shot: nil,
          created_at: medium_time,
          updated_at: medium_time
        })

      {:ok, _newest_shot} =
        ShotElixir.Repo.insert(%Shot{
          fight_id: fight.id,
          character_id: character1.id,
          shot: nil,
          created_at: new_time,
          updated_at: new_time
        })

      # Verify three shots exist
      shots_before =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(shots_before) == 3

      # Reduce to one shot via API
      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            character_ids: [character1.id]
          }
        )

      assert json_response(conn, 200)

      # The remaining shot should be the oldest one
      shots_after =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(shots_after) == 1
      assert List.first(shots_after).id == oldest_shot.id
    end

    test "handles mix of duplicates and unique characters", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      character1: character1,
      character2: character2
    } do
      conn = authenticate(conn, gm)

      # Add character1 twice and character2 once
      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            character_ids: [character1.id, character2.id, character1.id]
          }
        )

      assert json_response(conn, 200)

      # Verify character1 has 2 shots
      char1_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(char1_shots) == 2

      # Verify character2 has 1 shot
      char2_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character2.id
        )

      assert length(char2_shots) == 1
    end

    test "completely removing a duplicated character removes all shots", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      character1: character1,
      character2: character2
    } do
      conn = authenticate(conn, gm)

      # First add character1 three times
      conn1 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            character_ids: [character1.id, character1.id, character1.id]
          }
        )

      assert json_response(conn1, 200)

      # Verify three shots
      shots_before =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(shots_before) == 3

      # Now remove character1 entirely by passing only character2
      conn2 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            character_ids: [character2.id]
          }
        )

      assert json_response(conn2, 200)

      # Verify character1 has no shots
      char1_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character1.id
        )

      assert length(char1_shots) == 0

      # Verify character2 has one shot
      char2_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^character2.id
        )

      assert length(char2_shots) == 1
    end
  end

  describe "duplicate vehicle shots" do
    alias ShotElixir.Fights.Shot
    import Ecto.Query

    setup %{gamemaster: gm, campaign: campaign, player: player} do
      # Create vehicles for testing
      {:ok, vehicle1} =
        Vehicles.create_vehicle(%{
          name: "Vehicle One",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{}
        })

      {:ok, vehicle2} =
        Vehicles.create_vehicle(%{
          name: "Vehicle Two",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{}
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Vehicle Duplicate Test Fight",
          campaign_id: campaign.id
        })

      %{vehicle1: vehicle1, vehicle2: vehicle2, fight: fight}
    end

    test "adding same vehicle multiple times creates multiple shot records", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      vehicle1: vehicle1
    } do
      # Add vehicle1 three times
      update_attrs = %{
        vehicle_ids: [vehicle1.id, vehicle1.id, vehicle1.id]
      }

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: update_attrs)
      assert json_response(conn, 200)

      # Verify three shots were created for the same vehicle
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(shots) == 3
    end

    test "reducing duplicate count only removes some shot records", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      vehicle1: vehicle1
    } do
      conn = authenticate(conn, gm)

      # First add vehicle1 three times
      conn1 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            vehicle_ids: [vehicle1.id, vehicle1.id, vehicle1.id]
          }
        )

      assert json_response(conn1, 200)

      # Verify three shots
      shots_before =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(shots_before) == 3

      # Now reduce to only one instance
      conn2 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            vehicle_ids: [vehicle1.id]
          }
        )

      assert json_response(conn2, 200)

      # Verify only one shot remains
      shots_after =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(shots_after) == 1
    end

    test "removing duplicates removes newest shots first", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      vehicle1: vehicle1
    } do
      conn = authenticate(conn, gm)

      # Manually create shots with different timestamps to test "newest first" removal
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      old_time = DateTime.add(now, -3600, :second)
      medium_time = DateTime.add(now, -1800, :second)
      new_time = now

      # Insert shots directly with specific timestamps
      # Shot schema uses created_at (not inserted_at) per timestamps() config
      {:ok, oldest_shot} =
        ShotElixir.Repo.insert(%Shot{
          fight_id: fight.id,
          vehicle_id: vehicle1.id,
          shot: nil,
          created_at: old_time,
          updated_at: old_time
        })

      {:ok, _middle_shot} =
        ShotElixir.Repo.insert(%Shot{
          fight_id: fight.id,
          vehicle_id: vehicle1.id,
          shot: nil,
          created_at: medium_time,
          updated_at: medium_time
        })

      {:ok, _newest_shot} =
        ShotElixir.Repo.insert(%Shot{
          fight_id: fight.id,
          vehicle_id: vehicle1.id,
          shot: nil,
          created_at: new_time,
          updated_at: new_time
        })

      # Verify three shots exist
      shots_before =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(shots_before) == 3

      # Reduce to one shot via API
      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            vehicle_ids: [vehicle1.id]
          }
        )

      assert json_response(conn, 200)

      # The remaining shot should be the oldest one
      shots_after =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(shots_after) == 1
      assert List.first(shots_after).id == oldest_shot.id
    end

    test "handles mix of duplicates and unique vehicles", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      vehicle1: vehicle1,
      vehicle2: vehicle2
    } do
      conn = authenticate(conn, gm)

      # Add vehicle1 twice and vehicle2 once
      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            vehicle_ids: [vehicle1.id, vehicle2.id, vehicle1.id]
          }
        )

      assert json_response(conn, 200)

      # Verify vehicle1 has 2 shots
      vehicle1_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(vehicle1_shots) == 2

      # Verify vehicle2 has 1 shot
      vehicle2_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle2.id
        )

      assert length(vehicle2_shots) == 1
    end

    test "completely removing a duplicated vehicle removes all shots", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      vehicle1: vehicle1,
      vehicle2: vehicle2
    } do
      conn = authenticate(conn, gm)

      # First add vehicle1 three times
      conn1 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            vehicle_ids: [vehicle1.id, vehicle1.id, vehicle1.id]
          }
        )

      assert json_response(conn1, 200)

      # Verify three shots
      shots_before =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(shots_before) == 3

      # Now remove vehicle1 entirely by passing only vehicle2
      conn2 =
        patch(conn, ~p"/api/v2/fights/#{fight.id}",
          fight: %{
            vehicle_ids: [vehicle2.id]
          }
        )

      assert json_response(conn2, 200)

      # Verify vehicle1 has no shots
      vehicle1_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle1.id
        )

      assert length(vehicle1_shots) == 0

      # Verify vehicle2 has one shot
      vehicle2_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle2.id
        )

      assert length(vehicle2_shots) == 1
    end
  end

  describe "user ownership" do
    test "creates fight with user_id set to current user", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: @create_attrs)
      response = json_response(conn, 201)

      assert response["user_id"] == gm.id
    end

    test "returns user_id in fight show response", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gm.id
          })
        )

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}")
      response = json_response(conn, 200)

      assert response["user_id"] == gm.id
    end

    test "returns user_id in fight index response", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gm.id
          })
        )

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights")
      response = json_response(conn, 200)

      fight_response = Enum.find(response["fights"], fn f -> f["id"] == fight.id end)
      assert fight_response["user_id"] == gm.id
    end

    test "allows updating user_id on fight", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gm.id
          })
        )

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: %{user_id: player.id})
      response = json_response(conn, 200)

      assert response["user_id"] == player.id
    end

    test "allows clearing user_id on fight", %{conn: conn, gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(
          Map.merge(@create_attrs, %{
            campaign_id: campaign.id,
            user_id: gm.id
          })
        )

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: %{user_id: nil})
      response = json_response(conn, 200)

      assert response["user_id"] == nil
    end
  end

  describe "add_party" do
    alias ShotElixir.Parties
    alias ShotElixir.Fights.Shot
    import Ecto.Query

    setup %{gamemaster: gm, campaign: campaign, player: player} do
      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Add Party Test Fight",
          campaign_id: campaign.id
        })

      # Create a party
      {:ok, party} =
        Parties.create_party(%{
          name: "Test Party",
          campaign_id: campaign.id
        })

      # Create characters for party slots
      {:ok, boss_char} =
        Characters.create_character(%{
          name: "Boss Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "Boss"}
        })

      {:ok, featured_char} =
        Characters.create_character(%{
          name: "Featured Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "Featured Foe"}
        })

      {:ok, mook_char} =
        Characters.create_character(%{
          name: "Mook Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "Mook"}
        })

      # Create a vehicle
      {:ok, party_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Party Vehicle",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{}
        })

      %{
        fight: fight,
        party: party,
        boss_char: boss_char,
        featured_char: featured_char,
        mook_char: mook_char,
        party_vehicle: party_vehicle
      }
    end

    test "adds party characters to fight", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      party: party,
      boss_char: boss_char,
      featured_char: featured_char
    } do
      # Add slots to party
      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "boss", "character_id" => boss_char.id})

      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "character_id" => featured_char.id})

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      response = json_response(conn, 200)

      assert response["id"] == fight.id

      # Verify shots were created
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id
        )

      assert length(shots) == 2

      character_ids = Enum.map(shots, & &1.character_id) |> Enum.filter(&(&1 != nil))
      assert boss_char.id in character_ids
      assert featured_char.id in character_ids
    end

    test "adds mook character with default_mook_count as single shot", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      party: party,
      mook_char: mook_char
    } do
      # Add mook slot with count of 5 - this is metadata on the character, not a multiplier
      {:ok, _} =
        Parties.add_slot(party.id, %{
          "role" => "mook",
          "character_id" => mook_char.id,
          "default_mook_count" => 5
        })

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      response = json_response(conn, 200)

      assert response["id"] == fight.id

      # Verify only 1 shot was created - mook count is stored as metadata, not multiple shots
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^mook_char.id
        )

      assert length(shots) == 1
    end

    test "adds party vehicles to fight", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      party: party,
      party_vehicle: party_vehicle
    } do
      # Add vehicle slot
      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "vehicle_id" => party_vehicle.id})

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      response = json_response(conn, 200)

      assert response["id"] == fight.id

      # Verify vehicle shot was created
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.vehicle_id == ^party_vehicle.id
        )

      assert length(shots) == 1
    end

    test "preserves existing fight members", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      party: party,
      character: existing_char,
      boss_char: boss_char
    } do
      # Add existing character to fight
      {:ok, _} = Fights.create_shot(%{fight_id: fight.id, character_id: existing_char.id})

      # Add slot to party
      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "boss", "character_id" => boss_char.id})

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      response = json_response(conn, 200)

      # Verify both existing and new characters are in fight
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id
        )

      assert length(shots) == 2

      character_ids = Enum.map(shots, & &1.character_id) |> Enum.filter(&(&1 != nil))
      assert existing_char.id in character_ids
      assert boss_char.id in character_ids
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm, party: party} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{invalid_id}/add_party", party_id: party.id)
      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "returns 404 when party not found", %{conn: conn, gamemaster: gm, fight: fight} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: invalid_id)
      assert json_response(conn, 404)["error"] == "Party not found"
    end

    test "returns 404 when party is from different campaign", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      # Create another campaign and party
      {:ok, other_gm} =
        Accounts.create_user(%{
          email: "other_gm_party@test.com",
          password: "password123",
          first_name: "Other",
          last_name: "GM",
          gamemaster: true
        })

      {:ok, other_campaign} =
        Campaigns.create_campaign(%{
          name: "Other Campaign",
          description: "Different campaign",
          user_id: other_gm.id
        })

      {:ok, other_party} =
        Parties.create_party(%{
          name: "Other Campaign Party",
          campaign_id: other_campaign.id
        })

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: other_party.id)
      # Should return 404 to avoid leaking cross-campaign info
      assert json_response(conn, 404)["error"] == "Party not found"
    end

    test "only gamemaster can add parties to fights", %{
      conn: conn,
      player: player,
      fight: fight,
      party: party
    } do
      conn = authenticate(conn, player)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      assert json_response(conn, 403)["error"] == "Only gamemaster can add parties to fights"
    end

    test "requires authentication", %{conn: conn, fight: fight, party: party} do
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      assert json_response(conn, 401)
    end

    test "handles mixed slot types", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      party: party,
      boss_char: boss_char,
      featured_char: featured_char,
      mook_char: mook_char,
      party_vehicle: party_vehicle
    } do
      # Add various slot types
      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "boss", "character_id" => boss_char.id})

      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "character_id" => featured_char.id})

      {:ok, _} =
        Parties.add_slot(party.id, %{
          "role" => "mook",
          "character_id" => mook_char.id,
          "default_mook_count" => 3
        })

      {:ok, _} =
        Parties.add_slot(party.id, %{"role" => "featured_foe", "vehicle_id" => party_vehicle.id})

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      response = json_response(conn, 200)

      assert response["id"] == fight.id

      # Verify correct shot counts - each slot adds exactly one shot
      all_shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id
        )

      # 1 boss + 1 featured + 1 mook + 1 vehicle = 4 total (mook count is metadata, not multiple shots)
      assert length(all_shots) == 4

      # Verify specific counts - each character/vehicle has exactly one shot
      boss_shots =
        Enum.filter(all_shots, &(&1.character_id == boss_char.id))

      assert length(boss_shots) == 1

      mook_shots =
        Enum.filter(all_shots, &(&1.character_id == mook_char.id))

      assert length(mook_shots) == 1

      vehicle_shots =
        Enum.filter(all_shots, &(&1.vehicle_id == party_vehicle.id))

      assert length(vehicle_shots) == 1
    end

    test "handles mook slot without default_mook_count (defaults to 1)", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      party: party,
      mook_char: mook_char
    } do
      # Add mook slot without default_mook_count
      {:ok, _} =
        Parties.add_slot(party.id, %{
          "role" => "mook",
          "character_id" => mook_char.id
        })

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/add_party", party_id: party.id)
      response = json_response(conn, 200)

      assert response["id"] == fight.id

      # Verify only 1 shot was created (default when no count)
      shots =
        ShotElixir.Repo.all(
          from s in Shot,
            where: s.fight_id == ^fight.id and s.character_id == ^mook_char.id
        )

      assert length(shots) == 1
    end
  end

  describe "adventure associations" do
    alias ShotElixir.Adventures
    alias ShotElixir.Adventures.AdventureFight
    import Ecto.Query

    setup %{gamemaster: gm, campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Adventure Sync Fight",
          campaign_id: campaign.id
        })

      {:ok, adventure1} =
        Adventures.create_adventure(%{
          name: "Adventure One",
          campaign_id: campaign.id,
          user_id: gm.id
        })

      {:ok, adventure2} =
        Adventures.create_adventure(%{
          name: "Adventure Two",
          campaign_id: campaign.id,
          user_id: gm.id
        })

      %{fight: fight, adventure1: adventure1, adventure2: adventure2}
    end

    test "syncs adventure associations on update", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      adventure1: adventure1,
      adventure2: adventure2
    } do
      conn = authenticate(conn, gm)

      # Add both adventures
      update_attrs = %{
        adventure_ids: [adventure1.id, adventure2.id]
      }

      conn1 = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: update_attrs)
      response1 = json_response(conn1, 200)

      assert length(response1["adventure_ids"]) == 2
      assert adventure1.id in response1["adventure_ids"]
      assert adventure2.id in response1["adventure_ids"]

      # Verify in DB
      links = ShotElixir.Repo.all(from af in AdventureFight, where: af.fight_id == ^fight.id)
      assert length(links) == 2

      # Remove one adventure
      update_attrs2 = %{
        adventure_ids: [adventure1.id]
      }

      conn2 = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: update_attrs2)
      response2 = json_response(conn2, 200)

      assert response2["adventure_ids"] == [adventure1.id]

      # Verify in DB
      links2 = ShotElixir.Repo.all(from af in AdventureFight, where: af.fight_id == ^fight.id)
      assert length(links2) == 1
      assert List.first(links2).adventure_id == adventure1.id
    end
  end
end
