defmodule ShotElixirWeb.Api.V2.CharacterControllerFilteringTest do
  use ShotElixirWeb.ConnCase

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts,
    Factions,
    Junctures,
    Parties,
    Sites,
    Fights
  }

  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, player} =
      Accounts.create_user(%{
        email: "player@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign for characters",
        user_id: gamemaster.id
      })

    # Set campaign as current for users
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     player: player_with_campaign,
     campaign: campaign}
  end

  describe "index filtering and sorting" do
    setup %{gamemaster: gm, campaign: campaign} do
      # Create factions
      {:ok, dragons} =
        Factions.create_faction(%{
          name: "The Dragons",
          description: "A bunch of heroes",
          campaign_id: campaign.id
        })

      {:ok, ascended} =
        Factions.create_faction(%{
          name: "The Ascended",
          description: "A bunch of villains",
          campaign_id: campaign.id
        })

      # Create junctures
      {:ok, modern} =
        Junctures.create_juncture(%{
          name: "Modern",
          description: "The modern world",
          campaign_id: campaign.id
        })

      {:ok, ancient} =
        Junctures.create_juncture(%{
          name: "Ancient",
          description: "The ancient world",
          campaign_id: campaign.id
        })

      # Create parties
      {:ok, dragons_party} =
        Parties.create_party(%{
          name: "Dragons Party",
          campaign_id: campaign.id,
          faction_id: dragons.id
        })

      # Create sites
      {:ok, dragons_hq} =
        Sites.create_site(%{
          name: "Dragons HQ",
          description: "The Dragons' headquarters",
          campaign_id: campaign.id,
          faction_id: dragons.id
        })

      # Create fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Big Brawl",
          campaign_id: campaign.id
        })

      # Create characters
      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: dragons.id,
          juncture_id: modern.id,
          action_values: %{
            "Type" => "PC",
            "Archetype" => "Everyday Hero",
            "Martial Arts" => 13,
            "MainAttack" => "Martial Arts"
          },
          description: %{"Appearance" => "He's Brick Manly, son"}
        })

      {:ok, serena} =
        Characters.create_character(%{
          name: "Serena",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: dragons.id,
          juncture_id: ancient.id,
          action_values: %{"Type" => "PC", "Archetype" => "Sorcerer"}
        })

      {:ok, boss} =
        Characters.create_character(%{
          name: "Ugly Shing",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: ascended.id,
          action_values: %{"Type" => "Boss"}
        })

      {:ok, featured_foe} =
        Characters.create_character(%{
          name: "Amanda Yin",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: ascended.id,
          action_values: %{"Type" => "Featured Foe"}
        })

      {:ok, mook} =
        Characters.create_character(%{
          name: "Thug",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: ascended.id,
          action_values: %{"Type" => "Mook"}
        })

      {:ok, ally} =
        Characters.create_character(%{
          name: "Angie Lo",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: dragons.id,
          action_values: %{"Type" => "Ally"}
        })

      {:ok, _dead_guy} =
        Characters.create_character(%{
          name: "Dead Guy",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: dragons.id,
          active: false,
          action_values: %{"Type" => "PC", "Archetype" => "Everyday Hero"}
        })

      %{
        dragons: dragons,
        ascended: ascended,
        modern: modern,
        ancient: ancient,
        dragons_party: dragons_party,
        dragons_hq: dragons_hq,
        fight: fight,
        brick: brick,
        serena: serena,
        boss: boss,
        featured_foe: featured_foe,
        mook: mook,
        ally: ally
      }
    end

    test "filters by faction_id", %{
      conn: conn,
      gamemaster: gm,
      dragons: dragons
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", faction_id: dragons.id)
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Brick Manly" in names
      assert "Serena" in names
      assert "Angie Lo" in names
      refute "Ugly Shing" in names
      refute "Thug" in names
    end

    test "filters by __NONE__ faction", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, _no_faction_char} =
        Characters.create_character(%{
          name: "No Faction Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          faction_id: nil,
          action_values: %{"Type" => "PC"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", faction_id: "__NONE__")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "No Faction Character" in names
      refute "Brick Manly" in names
    end

    test "filters by user_id", %{
      conn: conn,
      gamemaster: gm,
      player: player,
      campaign: campaign
    } do
      {:ok, _player_char} =
        Characters.create_character(%{
          name: "Player Character",
          campaign_id: campaign.id,
          user_id: player.id,
          action_values: %{"Type" => "PC"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", user_id: player.id)
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Player Character" in names
      refute "Brick Manly" in names
    end

    test "filters by juncture_id", %{
      conn: conn,
      gamemaster: gm,
      modern: modern
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", juncture_id: modern.id)
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Brick Manly" in names
      refute "Serena" in names
    end

    test "filters by __NONE__ juncture", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign
    } do
      {:ok, _} =
        Characters.create_character(%{
          name: "No Juncture Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          juncture_id: nil,
          action_values: %{"Type" => "PC"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", juncture_id: "__NONE__")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "No Juncture Character" in names
      # Characters without juncture_id should appear
      refute "Brick Manly" in names
    end

    test "filters by character_type", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", character_type: "Boss")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Ugly Shing" in names
      assert length(names) == 1
    end

    test "filters by PC character type", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", character_type: "PC")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Brick Manly" in names
      assert "Serena" in names
      refute "Ugly Shing" in names
    end

    test "filters by archetype", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", archetype: "Sorcerer")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert names == ["Serena"]
    end

    test "filters by party_id", %{
      conn: conn,
      gamemaster: gm,
      dragons_party: dragons_party,
      brick: brick
    } do
      # Add brick to the party via membership
      {:ok, _} =
        Parties.add_member(dragons_party.id, %{"character_id" => brick.id})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", party_id: dragons_party.id)
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert names == ["Brick Manly"]
    end

    test "filters by site_id", %{
      conn: conn,
      gamemaster: gm,
      dragons_hq: dragons_hq,
      brick: brick,
      serena: serena
    } do
      # Attune characters to site via attunement
      {:ok, _} = Sites.create_attunement(%{site_id: dragons_hq.id, character_id: brick.id})
      {:ok, _} = Sites.create_attunement(%{site_id: dragons_hq.id, character_id: serena.id})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", site_id: dragons_hq.id)
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Brick Manly" in names
      assert "Serena" in names
      refute "Ugly Shing" in names
    end

    test "filters by fight_id", %{
      conn: conn,
      gamemaster: gm,
      fight: fight,
      brick: brick,
      serena: serena,
      boss: boss
    } do
      # Add characters to fight via shots
      {:ok, _} = Fights.create_shot(%{fight_id: fight.id, character_id: brick.id, shot: 10})
      {:ok, _} = Fights.create_shot(%{fight_id: fight.id, character_id: serena.id, shot: 8})
      {:ok, _} = Fights.create_shot(%{fight_id: fight.id, character_id: boss.id, shot: 12})

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", fight_id: fight.id, sort: "name", order: "asc")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Brick Manly" in names
      assert "Serena" in names
      assert "Ugly Shing" in names
      refute "Thug" in names
    end

    test "filters by single id", %{
      conn: conn,
      gamemaster: gm,
      brick: brick
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", id: brick.id)
      response = json_response(conn, 200)

      assert length(response["characters"]) == 1
      assert hd(response["characters"])["name"] == "Brick Manly"
    end

    test "filters by comma-separated ids", %{
      conn: conn,
      gamemaster: gm,
      brick: brick,
      serena: serena
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", ids: "#{brick.id},#{serena.id}")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert length(names) == 2
      assert "Brick Manly" in names
      assert "Serena" in names
    end

    test "returns empty array when ids is explicitly empty", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", ids: "")
      response = json_response(conn, 200)

      assert response["characters"] == []
      assert response["meta"]["total_count"] == 0
    end

    test "sorts by name ascending", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "name", order: "asc")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert names == Enum.sort(names)
    end

    test "sorts by name descending", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "name", order: "desc")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert names == Enum.sort(names, :desc)
    end

    test "sorts by created_at ascending", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "created_at", order: "asc")
      response = json_response(conn, 200)

      # Verify ordering is ascending by checking created_at timestamps
      created_ats =
        response["characters"]
        |> Enum.map(& &1["created_at"])
        |> Enum.reject(&is_nil/1)

      assert created_ats == Enum.sort(created_ats, :asc)
    end

    test "sorts by created_at descending", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "created_at", order: "desc")
      response = json_response(conn, 200)

      # Verify ordering is descending by checking created_at timestamps
      created_ats =
        response["characters"]
        |> Enum.map(& &1["created_at"])
        |> Enum.reject(&is_nil/1)

      assert created_ats == Enum.sort(created_ats, :desc)
    end

    test "sorts by type ascending", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "type", order: "asc")
      response = json_response(conn, 200)

      types = Enum.map(response["characters"], fn c -> c["action_values"]["Type"] end)
      # Ally comes first alphabetically
      assert List.first(types) == "Ally"
    end

    test "sorts by archetype ascending", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "archetype", order: "asc")
      response = json_response(conn, 200)

      # Characters with empty archetypes come first, then alphabetically
      names = Enum.map(response["characters"], & &1["name"])
      # Everyday Hero comes before Sorcerer alphabetically
      brick_idx = Enum.find_index(names, &(&1 == "Brick Manly"))
      serena_idx = Enum.find_index(names, &(&1 == "Serena"))
      assert brick_idx < serena_idx
    end

    test "sorts by faction ascending", %{
      conn: conn,
      gamemaster: gm,
      dragons: dragons,
      ascended: ascended
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "faction", order: "asc")
      response = json_response(conn, 200)

      # Characters sorted by faction name alphabetically
      # "The Ascended" comes before "The Dragons" alphabetically
      faction_ids = Enum.map(response["characters"], & &1["faction_id"])
      first_faction_idx = Enum.find_index(faction_ids, &(&1 == ascended.id))
      dragons_faction_idx = Enum.find_index(faction_ids, &(&1 == dragons.id))

      # Ascended characters should appear before Dragons characters
      assert first_faction_idx < dragons_faction_idx
    end

    test "sorts by faction descending", %{
      conn: conn,
      gamemaster: gm,
      dragons: dragons,
      ascended: ascended
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "faction", order: "desc")
      response = json_response(conn, 200)

      # Characters sorted by faction name descending
      # "The Dragons" comes before "The Ascended" in descending order
      faction_ids = Enum.map(response["characters"], & &1["faction_id"])
      dragons_faction_idx = Enum.find_index(faction_ids, &(&1 == dragons.id))
      ascended_faction_idx = Enum.find_index(faction_ids, &(&1 == ascended.id))

      # Dragons characters should appear before Ascended characters
      assert dragons_faction_idx < ascended_faction_idx
    end

    test "sorts by juncture ascending", %{
      conn: conn,
      gamemaster: gm,
      brick: brick,
      serena: serena
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "juncture", order: "asc")
      response = json_response(conn, 200)

      # Characters sorted by juncture name alphabetically
      # Serena has "Ancient" juncture, Brick has "Modern" juncture
      # "Ancient" comes before "Modern" alphabetically
      names = Enum.map(response["characters"], & &1["name"])
      serena_idx = Enum.find_index(names, &(&1 == serena.name))
      brick_idx = Enum.find_index(names, &(&1 == brick.name))

      # Serena (Ancient) should appear before Brick (Modern)
      assert serena_idx < brick_idx
    end

    test "sorts by juncture descending", %{
      conn: conn,
      gamemaster: gm,
      brick: brick,
      serena: serena
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", sort: "juncture", order: "desc")
      response = json_response(conn, 200)

      # Characters sorted by juncture name descending
      # "Modern" comes before "Ancient" in descending order
      names = Enum.map(response["characters"], & &1["name"])
      brick_idx = Enum.find_index(names, &(&1 == brick.name))
      serena_idx = Enum.find_index(names, &(&1 == serena.name))

      # Brick (Modern) should appear before Serena (Ancient)
      assert brick_idx < serena_idx
    end

    test "gets only active characters when show_hidden is false", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", show_hidden: "false")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      refute "Dead Guy" in names
    end

    test "gets all characters when show_hidden is true", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", show_hidden: "true")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Dead Guy" in names
    end

    test "pagination works correctly", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters", per_page: 2, page: 1, sort: "name", order: "asc")
      response = json_response(conn, 200)

      assert length(response["characters"]) == 2
      assert response["meta"]["current_page"] == 1
      assert response["meta"]["per_page"] == 2
      assert response["meta"]["total_pages"] > 1
    end

    test "returns factions in response", %{
      conn: conn,
      gamemaster: gm
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters")
      response = json_response(conn, 200)

      assert is_list(response["factions"])
      faction_names = Enum.map(response["factions"], & &1["name"])
      assert "The Dragons" in faction_names
      assert "The Ascended" in faction_names
    end
  end

  describe "template filtering" do
    setup %{gamemaster: gm, campaign: campaign} do
      # Create admin user
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin_template@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          gamemaster: false,
          admin: true
        })

      {:ok, admin_with_campaign} = Accounts.set_current_campaign(admin, campaign.id)
      {:ok, _} = Campaigns.add_member(campaign, admin)

      # Create template character
      {:ok, template} =
        Characters.create_character(%{
          name: "Bandit Template",
          campaign_id: campaign.id,
          user_id: gm.id,
          is_template: true,
          action_values: %{"Type" => "PC", "Archetype" => "Bandit"}
        })

      # Create regular character
      {:ok, regular} =
        Characters.create_character(%{
          name: "Regular Character",
          campaign_id: campaign.id,
          user_id: gm.id,
          is_template: false,
          action_values: %{"Type" => "PC"}
        })

      %{admin: admin_with_campaign, template: template, regular: regular}
    end

    test "admin can filter to see only templates", %{
      conn: conn,
      admin: admin
    } do
      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/characters", template_filter: "templates")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Bandit Template" in names
      refute "Regular Character" in names
    end

    test "admin can filter to see all characters", %{
      conn: conn,
      admin: admin
    } do
      conn = authenticate(conn, admin)
      conn = get(conn, ~p"/api/v2/characters", template_filter: "all")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      assert "Bandit Template" in names
      assert "Regular Character" in names
    end

    test "non-admin cannot see templates", %{
      conn: conn,
      player: player
    } do
      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/characters", template_filter: "templates")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      refute "Bandit Template" in names
    end

    test "default excludes templates for regular users", %{
      conn: conn,
      player: player
    } do
      conn = authenticate(conn, player)
      conn = get(conn, ~p"/api/v2/characters")
      response = json_response(conn, 200)

      names = Enum.map(response["characters"], & &1["name"])
      refute "Bandit Template" in names
      assert "Regular Character" in names
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
