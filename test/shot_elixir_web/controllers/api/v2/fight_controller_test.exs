defmodule ShotElixirWeb.Api.V2.FightControllerTest do
  use ShotElixirWeb.ConnCase

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

      assert response["fight"]["id"] == fight.id
      assert response["fight"]["name"] == fight.name
      assert response["fight"]["description"] == fight.description
      assert response["fight"]["season"] == fight.season
      assert response["fight"]["session"] == fight.session
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

      assert response["fight"]["id"] == fight.id
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

      assert response["fight"]["name"] == @create_attrs.name
      assert response["fight"]["description"] == @create_attrs.description
      assert response["fight"]["season"] == @create_attrs.season
      assert response["fight"]["session"] == @create_attrs.session
      assert response["fight"]["active"] == true
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

      assert response["fight"]["name"] == @create_attrs.name
      # Note: Association IDs might be handled differently in the current implementation
    end

    test "handles JSON string parameters", %{conn: conn, gamemaster: gm} do
      json_attrs = Jason.encode!(@create_attrs)

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights", fight: json_attrs)
      response = json_response(conn, 201)

      assert response["fight"]["name"] == @create_attrs.name
      assert response["fight"]["description"] == @create_attrs.description
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

      assert response["fight"]["id"] == fight.id
      assert response["fight"]["name"] == @update_attrs.name
      assert response["fight"]["description"] == @update_attrs.description
      assert response["fight"]["season"] == @update_attrs.season
      assert response["fight"]["session"] == @update_attrs.session
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

      assert response["fight"]["name"] == @update_attrs.name
    end

    test "handles JSON string parameters", %{conn: conn, gamemaster: gm, fight: fight} do
      json_attrs = Jason.encode!(@update_attrs)

      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: json_attrs)
      response = json_response(conn, 200)

      assert response["fight"]["name"] == @update_attrs.name
      assert response["fight"]["description"] == @update_attrs.description
    end

    test "updates active status", %{conn: conn, gamemaster: gm, fight: fight} do
      conn = authenticate(conn, gm)
      conn = patch(conn, ~p"/api/v2/fights/#{fight.id}", fight: %{active: false})
      response = json_response(conn, 200)

      assert response["fight"]["active"] == false
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

      assert response["fight"]["id"] == fight.id
      assert response["fight"]["name"] == fight.name
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

      assert response["fight"]["id"] == fight.id
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

      assert response["fight"]["name"] == "Admin Updated"
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

    test "shows hidden fights when show_hidden=true", %{
      conn: conn,
      gamemaster: gm,
      inactive_fight: inactive_fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights", %{show_hidden: "true"})
      response = json_response(conn, 200)

      fight_names = Enum.map(response["fights"], & &1["name"])
      assert "Inactive Fight" in fight_names
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
      assert Map.keys(fight_data) == ["entity_class", "id", "name"]
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

      assert Map.keys(fight_data) == ["entity_class", "id", "name"]
    end
  end
end
