defmodule ShotElixirWeb.Api.V2.NotionSyncLogControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{
    Accounts,
    Campaigns,
    Characters,
    Factions,
    Junctures,
    Notion,
    Parties,
    Repo,
    Sites
  }

  alias ShotElixir.Notion.NotionSyncLog
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
        description: "Test campaign",
        user_id: gamemaster.id
      })

    {:ok, _} = Campaigns.add_member(campaign, player)

    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: player.id,
        action_values: %{"Type" => "PC"}
      })

    {:ok, site} =
      Sites.create_site(%{
        name: "Test Site",
        campaign_id: campaign.id
      })

    {:ok, party} =
      Parties.create_party(%{
        name: "Test Party",
        campaign_id: campaign.id
      })

    {:ok, faction} =
      Factions.create_faction(%{
        name: "Test Faction",
        campaign_id: campaign.id
      })

    {:ok, juncture} =
      Junctures.create_juncture(%{
        name: "Test Juncture",
        campaign_id: campaign.id
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gamemaster,
     player: player,
     campaign: campaign,
     character: character,
     site: site,
     party: party,
     faction: faction,
     juncture: juncture}
  end

  describe "index" do
    test "lists sync logs for a character", %{conn: conn, gamemaster: gm, character: character} do
      {:ok, _log} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: character.id,
          character_id: character.id,
          status: "success",
          payload: %{test: "data"},
          response: %{notion_id: "123"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs")
      response = json_response(conn, 200)

      assert length(response["notion_sync_logs"]) == 1
      assert response["meta"]["total_count"] == 1
    end

    test "lists sync logs for a site", %{conn: conn, gamemaster: gm, site: site} do
      {:ok, _log} =
        Notion.create_sync_log(%{
          entity_type: "site",
          entity_id: site.id,
          status: "success",
          payload: %{test: "data"},
          response: %{notion_id: "456"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/sites/#{site.id}/notion_sync_logs")
      response = json_response(conn, 200)

      assert length(response["notion_sync_logs"]) == 1
      assert response["meta"]["total_count"] == 1
    end

    test "lists sync logs for a party", %{conn: conn, gamemaster: gm, party: party} do
      {:ok, _log} =
        Notion.create_sync_log(%{
          entity_type: "party",
          entity_id: party.id,
          status: "success",
          payload: %{test: "data"},
          response: %{notion_id: "789"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/parties/#{party.id}/notion_sync_logs")
      response = json_response(conn, 200)

      assert length(response["notion_sync_logs"]) == 1
      assert response["meta"]["total_count"] == 1
    end

    test "lists sync logs for a faction", %{conn: conn, gamemaster: gm, faction: faction} do
      {:ok, _log} =
        Notion.create_sync_log(%{
          entity_type: "faction",
          entity_id: faction.id,
          status: "success",
          payload: %{test: "data"},
          response: %{notion_id: "012"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/factions/#{faction.id}/notion_sync_logs")
      response = json_response(conn, 200)

      assert length(response["notion_sync_logs"]) == 1
      assert response["meta"]["total_count"] == 1
    end

    test "lists sync logs for a juncture", %{conn: conn, gamemaster: gm, juncture: juncture} do
      {:ok, _log} =
        Notion.create_sync_log(%{
          entity_type: "juncture",
          entity_id: juncture.id,
          status: "success",
          payload: %{test: "data"},
          response: %{notion_id: "123"}
        })

      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/junctures/#{juncture.id}/notion_sync_logs")
      response = json_response(conn, 200)

      assert length(response["notion_sync_logs"]) == 1
      assert response["meta"]["total_count"] == 1
    end

    test "returns 403 for unauthorized player", %{conn: conn, character: character} do
      {:ok, other_player} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "Player",
          gamemaster: false
        })

      conn = authenticate(conn, other_player)
      conn = get(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs")
      assert json_response(conn, 403)
    end
  end

  describe "prune" do
    test "prunes old sync logs for character", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create an old log (40 days ago)
      {:ok, old_log} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: character.id,
          character_id: character.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      old_log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      # Create a recent log (10 days ago)
      {:ok, recent_log} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: character.id,
          character_id: character.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      recent_log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -10, :day)})
      |> Repo.update!()

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs/prune")
      response = json_response(conn, 200)

      assert response["pruned_count"] == 1
      assert Repo.get(NotionSyncLog, old_log.id) == nil
      assert Repo.get(NotionSyncLog, recent_log.id) != nil
    end

    test "prunes old sync logs for site", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create an old log (40 days ago)
      {:ok, old_log} =
        Notion.create_sync_log(%{
          entity_type: "site",
          entity_id: site.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      old_log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/sites/#{site.id}/notion_sync_logs/prune")
      response = json_response(conn, 200)

      assert response["pruned_count"] == 1
      assert Repo.get(NotionSyncLog, old_log.id) == nil
    end

    test "prunes old sync logs for party", %{
      conn: conn,
      gamemaster: gm,
      party: party
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create an old log (40 days ago)
      {:ok, old_log} =
        Notion.create_sync_log(%{
          entity_type: "party",
          entity_id: party.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      old_log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/parties/#{party.id}/notion_sync_logs/prune")
      response = json_response(conn, 200)

      assert response["pruned_count"] == 1
      assert Repo.get(NotionSyncLog, old_log.id) == nil
    end

    test "prunes old sync logs for faction", %{
      conn: conn,
      gamemaster: gm,
      faction: faction
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create an old log (40 days ago)
      {:ok, old_log} =
        Notion.create_sync_log(%{
          entity_type: "faction",
          entity_id: faction.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      old_log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/factions/#{faction.id}/notion_sync_logs/prune")
      response = json_response(conn, 200)

      assert response["pruned_count"] == 1
      assert Repo.get(NotionSyncLog, old_log.id) == nil
    end

    test "prunes old sync logs for juncture", %{
      conn: conn,
      gamemaster: gm,
      juncture: juncture
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create an old log (40 days ago)
      {:ok, old_log} =
        Notion.create_sync_log(%{
          entity_type: "juncture",
          entity_id: juncture.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      old_log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/junctures/#{juncture.id}/notion_sync_logs/prune")
      response = json_response(conn, 200)

      assert response["pruned_count"] == 1
      assert Repo.get(NotionSyncLog, old_log.id) == nil
    end

    test "prunes with custom days_old parameter", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create a log from 8 days ago
      {:ok, log} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: character.id,
          character_id: character.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      log
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -8, :day)})
      |> Repo.update!()

      conn = authenticate(conn, gm)

      conn =
        delete(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs/prune?days_old=7")

      response = json_response(conn, 200)

      assert response["pruned_count"] == 1
      assert response["days_old"] == 7

      # Verify log is deleted
      assert Repo.get(NotionSyncLog, log.id) == nil
    end

    test "returns 0 count when no logs to prune", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      conn = authenticate(conn, gm)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs/prune")
      response = json_response(conn, 200)

      assert response["pruned_count"] == 0
      assert response["days_old"] == 30
    end

    test "returns 403 for unauthorized player", %{conn: conn, character: character} do
      {:ok, other_player} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "Player",
          gamemaster: false
        })

      conn = authenticate(conn, other_player)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs/prune")
      assert json_response(conn, 403)
    end

    test "returns 404 for non-existent entity", %{conn: conn, gamemaster: gm} do
      conn = authenticate(conn, gm)
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/v2/characters/#{non_existent_id}/notion_sync_logs/prune")
      assert json_response(conn, 404)
    end

    test "admin can prune any character's logs", %{conn: conn, character: character} do
      {:ok, admin} =
        Accounts.create_user(%{
          email: "admin@example.com",
          password: "password123",
          first_name: "Admin",
          last_name: "User",
          admin: true
        })

      conn = authenticate(conn, admin)
      conn = delete(conn, ~p"/api/v2/characters/#{character.id}/notion_sync_logs/prune")
      assert json_response(conn, 200)
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
