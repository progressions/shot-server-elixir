defmodule ShotElixir.NotionTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Notion
  alias ShotElixir.Notion.NotionSyncLog
  alias ShotElixir.{Accounts, Campaigns, Characters, Repo}

  describe "prune_sync_logs/3" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          description: "Test campaign",
          user_id: user.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, user: user, campaign: campaign, character: character}
    end

    test "deletes logs older than specified days", %{character: character} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create a log from 40 days ago
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

      # Create a log from 10 days ago (should not be deleted with default 30 days)
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

      # Prune logs older than 30 days
      {:ok, count} = Notion.prune_sync_logs("character", character.id, days_old: 30)

      assert count == 1

      # Verify old log is deleted
      assert Repo.get(NotionSyncLog, old_log.id) == nil

      # Verify recent log still exists
      assert Repo.get(NotionSyncLog, recent_log.id) != nil
    end

    test "uses default of 30 days when no option provided", %{character: character} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create a log from 31 days ago
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
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -31, :day)})
      |> Repo.update!()

      {:ok, count} = Notion.prune_sync_logs("character", character.id)

      assert count == 1
      assert Repo.get(NotionSyncLog, old_log.id) == nil
    end

    test "respects custom days_old parameter", %{character: character} do
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

      # Prune logs older than 7 days
      {:ok, count} = Notion.prune_sync_logs("character", character.id, days_old: 7)

      assert count == 1
      assert Repo.get(NotionSyncLog, log.id) == nil
    end

    test "only deletes logs for the specified character", %{
      character: character,
      campaign: campaign,
      user: user
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create another character
      {:ok, other_character} =
        Characters.create_character(%{
          name: "Other Character",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "NPC"}
        })

      # Create old log for first character
      {:ok, log1} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: character.id,
          character_id: character.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      log1
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      # Create old log for second character
      {:ok, log2} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: other_character.id,
          character_id: other_character.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      log2
      |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -40, :day)})
      |> Repo.update!()

      # Prune only first character's logs
      {:ok, count} = Notion.prune_sync_logs("character", character.id, days_old: 30)

      assert count == 1

      # Verify first character's log is deleted
      assert Repo.get(NotionSyncLog, log1.id) == nil

      # Verify second character's log still exists
      assert Repo.get(NotionSyncLog, log2.id) != nil
    end

    test "returns 0 when no logs to prune", %{character: character} do
      {:ok, count} = Notion.prune_sync_logs("character", character.id, days_old: 30)
      assert count == 0
    end

    test "returns 0 when all logs are newer than cutoff", %{character: character} do
      # Create a log from today
      {:ok, _log} =
        Notion.create_sync_log(%{
          entity_type: "character",
          entity_id: character.id,
          character_id: character.id,
          status: "success",
          payload: %{},
          response: %{}
        })

      {:ok, count} = Notion.prune_sync_logs("character", character.id, days_old: 30)
      assert count == 0
    end
  end
end
