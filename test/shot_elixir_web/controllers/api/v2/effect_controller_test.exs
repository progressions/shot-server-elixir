defmodule ShotElixirWeb.Api.V2.EffectControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Fights, Campaigns, Accounts, Effects}
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
        description: "Campaign for effect testing",
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
    test "returns effects for campaign owner", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      {:ok, _effect1} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Building On Fire",
          severity: "error",
          user_id: gm.id
        })

      {:ok, _effect2} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Reinforcements Coming",
          severity: "warning",
          user_id: gm.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/effects")
      response = json_response(conn, 200)

      assert is_list(response["effects"])
      assert length(response["effects"]) == 2
    end

    test "returns effects for campaign member", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      fight: fight
    } do
      {:ok, _effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Heavy Rain",
          severity: "info",
          user_id: gm.id
        })

      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/effects")
      response = json_response(conn, 200)

      assert is_list(response["effects"])
      assert length(response["effects"]) == 1
    end

    test "returns forbidden for non-member", %{
      conn: conn,
      non_member: non_member,
      fight: fight
    } do
      conn = authenticate(conn, non_member)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/effects")

      assert json_response(conn, 403)["error"] == "Not a member of this campaign"
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{invalid_id}/effects")

      assert json_response(conn, 404)["error"] == "Fight not found"
    end

    test "requires authentication", %{conn: conn, fight: fight} do
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/effects")
      assert json_response(conn, 401)
    end

    test "returns empty list when no effects exist", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/effects")
      response = json_response(conn, 200)

      assert response["effects"] == []
    end
  end

  describe "create" do
    test "creates effect when gamemaster", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      effect_params = %{
        "name" => "Building Collapsing",
        "description" => "The building is about to collapse!",
        "severity" => "error",
        "end_sequence" => 3,
        "end_shot" => 0
      }

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/effects", %{"effect" => effect_params})
      response = json_response(conn, 201)

      assert response["name"] == "Building Collapsing"
      assert response["description"] == "The building is about to collapse!"
      assert response["severity"] == "error"
      assert response["end_sequence"] == 3
      assert response["end_shot"] == 0
      assert response["fight_id"] == fight.id
      assert response["user_id"] == gm.id
    end

    test "returns forbidden when player tries to create", %{
      conn: conn,
      player: player,
      fight: fight
    } do
      effect_params = %{
        "name" => "Test Effect",
        "severity" => "info"
      }

      conn = authenticate(conn, player)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/effects", %{"effect" => effect_params})

      assert json_response(conn, 403)["error"] == "Only gamemaster can create fight effects"
    end

    test "admin can create effects", %{
      conn: conn,
      admin: admin,
      fight: fight
    } do
      effect_params = %{
        "name" => "Admin Created Effect",
        "severity" => "success"
      }

      conn = authenticate(conn, admin)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/effects", %{"effect" => effect_params})
      response = json_response(conn, 201)

      assert response["name"] == "Admin Created Effect"
    end

    test "returns error for invalid severity", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      effect_params = %{
        "name" => "Test Effect",
        "severity" => "invalid_severity"
      }

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{fight.id}/effects", %{"effect" => effect_params})
      response = json_response(conn, 422)

      assert response["errors"]["severity"] != nil
    end

    test "returns 404 when fight not found", %{conn: conn, gamemaster: gm} do
      invalid_id = Ecto.UUID.generate()

      effect_params = %{
        "name" => "Test Effect",
        "severity" => "info"
      }

      conn = authenticate(conn, gm)
      conn = post(conn, ~p"/api/v2/fights/#{invalid_id}/effects", %{"effect" => effect_params})

      assert json_response(conn, 404)["error"] == "Fight not found"
    end
  end

  describe "update" do
    test "updates effect when gamemaster", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      {:ok, effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Original Name",
          severity: "info",
          user_id: gm.id
        })

      update_params = %{
        "name" => "Updated Name",
        "severity" => "warning",
        "end_sequence" => 5
      }

      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{effect.id}", %{
          "effect" => update_params
        })

      response = json_response(conn, 200)

      assert response["name"] == "Updated Name"
      assert response["severity"] == "warning"
      assert response["end_sequence"] == 5
    end

    test "returns forbidden when player tries to update", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      fight: fight
    } do
      {:ok, effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Test Effect",
          severity: "info",
          user_id: gm.id
        })

      update_params = %{"name" => "Hacked Name"}

      conn = authenticate(conn, player)

      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{effect.id}", %{
          "effect" => update_params
        })

      assert json_response(conn, 403)["error"] == "Only gamemaster can update fight effects"
    end

    test "returns 404 when effect not found", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      invalid_id = Ecto.UUID.generate()
      update_params = %{"name" => "Test"}

      conn = authenticate(conn, gm)

      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{invalid_id}", %{
          "effect" => update_params
        })

      assert json_response(conn, 404)["error"] == "Fight or effect not found"
    end

    test "returns 404 when effect belongs to different fight", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      campaign: campaign
    } do
      # Create another fight
      {:ok, other_fight} =
        Fights.create_fight(%{
          name: "Other Fight",
          campaign_id: campaign.id
        })

      # Create effect on other fight
      {:ok, effect} =
        Effects.create_effect(%{
          fight_id: other_fight.id,
          name: "Other Effect",
          severity: "info",
          user_id: gm.id
        })

      update_params = %{"name" => "Updated"}

      conn = authenticate(conn, gm)
      # Try to update effect using wrong fight_id
      conn =
        patch(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{effect.id}", %{
          "effect" => update_params
        })

      assert json_response(conn, 404)["error"] == "Fight or effect not found"
    end
  end

  describe "delete" do
    test "deletes effect when gamemaster", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      {:ok, effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "To Be Deleted",
          severity: "info",
          user_id: gm.id
        })

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{effect.id}")

      assert response(conn, 200)

      # Verify effect is deleted
      assert Effects.get_effect(effect.id) == nil
    end

    test "returns forbidden when player tries to delete", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      fight: fight
    } do
      {:ok, effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Protected Effect",
          severity: "info",
          user_id: gm.id
        })

      conn = authenticate(conn, player)
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{effect.id}")

      assert json_response(conn, 403)["error"] == "Only gamemaster can delete fight effects"

      # Verify effect still exists
      assert Effects.get_effect(effect.id) != nil
    end

    test "admin can delete effects", %{
      conn: conn,
      gamemaster: gm,
      admin: admin,
      fight: fight
    } do
      {:ok, effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Admin Delete Test",
          severity: "info",
          user_id: gm.id
        })

      conn = authenticate(conn, admin)
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{effect.id}")

      assert response(conn, 200)
      assert Effects.get_effect(effect.id) == nil
    end

    test "returns 404 when effect not found", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      invalid_id = Ecto.UUID.generate()

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/fights/#{fight.id}/effects/#{invalid_id}")

      assert json_response(conn, 404)["error"] == "Fight or effect not found"
    end
  end

  describe "effect structure" do
    test "returns all expected fields", %{
      conn: conn,
      gamemaster: gm,
      fight: fight
    } do
      {:ok, _effect} =
        Effects.create_effect(%{
          fight_id: fight.id,
          name: "Complete Effect",
          description: "Full description",
          severity: "warning",
          start_sequence: 1,
          end_sequence: 3,
          start_shot: 12,
          end_shot: 6,
          user_id: gm.id
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/fights/#{fight.id}/effects")
      response = json_response(conn, 200)

      effect = List.first(response["effects"])
      assert Map.has_key?(effect, "id")
      assert Map.has_key?(effect, "name")
      assert Map.has_key?(effect, "description")
      assert Map.has_key?(effect, "severity")
      assert Map.has_key?(effect, "start_sequence")
      assert Map.has_key?(effect, "end_sequence")
      assert Map.has_key?(effect, "start_shot")
      assert Map.has_key?(effect, "end_shot")
      assert Map.has_key?(effect, "fight_id")
      assert Map.has_key?(effect, "user_id")
      assert Map.has_key?(effect, "created_at")

      assert effect["name"] == "Complete Effect"
      assert effect["description"] == "Full description"
      assert effect["severity"] == "warning"
      assert effect["start_sequence"] == 1
      assert effect["end_sequence"] == 3
      assert effect["start_shot"] == 12
      assert effect["end_shot"] == 6
    end
  end
end
