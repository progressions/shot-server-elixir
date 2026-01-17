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

  describe "failure threshold behavior" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "threshold_test@example.com",
          password: "password123",
          first_name: "Test",
          last_name: "User",
          gamemaster: true
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Threshold Test Campaign",
          description: "Testing failure thresholds",
          user_id: user.id,
          notion_status: "working"
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Threshold Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, user: user, campaign: campaign, character: character}
    end

    test "does not set needs_attention before reaching threshold", %{
      character: character,
      campaign: campaign
    } do
      # First failure - should NOT set needs_attention (threshold is 3)
      Notion.log_error("character", character.id, %{}, %{}, "Test error 1")

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      assert campaign.notion_status == "working"
      assert campaign.notion_failure_count == 1
      assert campaign.notion_failure_window_start != nil

      # Second failure - still should NOT set needs_attention
      Notion.log_error("character", character.id, %{}, %{}, "Test error 2")

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      assert campaign.notion_status == "working"
      assert campaign.notion_failure_count == 2
    end

    test "sets needs_attention when threshold is reached", %{
      character: character,
      campaign: campaign
    } do
      # Trigger 3 failures (default threshold)
      Notion.log_error("character", character.id, %{}, %{}, "Test error 1")
      Notion.log_error("character", character.id, %{}, %{}, "Test error 2")
      Notion.log_error("character", character.id, %{}, %{}, "Test error 3")

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      assert campaign.notion_status == "needs_attention"
      assert campaign.notion_failure_count == 3
    end

    test "resets window and counter when window expires", %{
      character: character,
      campaign: campaign
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Simulate 2 failures that happened 2 hours ago (outside the 1 hour window)
      {:ok, campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_failure_count: 2,
          notion_failure_window_start: DateTime.add(now, -2, :hour)
        })

      # Now trigger a new failure - should reset window and start count at 1
      Notion.log_error("character", character.id, %{}, %{}, "New error after window expired")

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      # Status should still be working because we only have 1 failure in new window
      assert campaign.notion_status == "working"
      # Count should be 1 (reset, not 3)
      assert campaign.notion_failure_count == 1
      # Window should be recent (within last minute)
      assert DateTime.diff(now, campaign.notion_failure_window_start, :second) < 60
    end

    test "success resets failure tracking counters", %{
      character: character,
      campaign: campaign
    } do
      # Set up some failure state
      {:ok, campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_failure_count: 2,
          notion_failure_window_start: DateTime.utc_now()
        })

      # Trigger a success
      Notion.log_success("character", character.id, %{}, %{})

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      # Counter should be reset
      assert campaign.notion_failure_count == 0
      # Window should be cleared
      assert campaign.notion_failure_window_start == nil
      # Status should remain working
      assert campaign.notion_status == "working"
    end

    test "success after needs_attention resets status to working", %{
      character: character,
      campaign: campaign
    } do
      # Set up needs_attention state with failure tracking
      {:ok, campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_status: "needs_attention",
          notion_failure_count: 3,
          notion_failure_window_start: DateTime.utc_now()
        })

      # Trigger a success
      Notion.log_success("character", character.id, %{}, %{})

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      # Status should be reset to working
      assert campaign.notion_status == "working"
      # Counter should be reset
      assert campaign.notion_failure_count == 0
      # Window should be cleared
      assert campaign.notion_failure_window_start == nil
    end

    test "does not send additional email if already needs_attention", %{
      character: character,
      campaign: campaign
    } do
      # Set campaign to needs_attention
      {:ok, _campaign} =
        Campaigns.update_campaign(campaign, %{
          notion_status: "needs_attention",
          notion_failure_count: 3,
          notion_failure_window_start: DateTime.utc_now()
        })

      # Trigger another failure - should not change anything
      Notion.log_error("character", character.id, %{}, %{}, "Another error")

      campaign = Repo.get!(Campaigns.Campaign, campaign.id)
      # Status should still be needs_attention
      assert campaign.notion_status == "needs_attention"
      # Count should not have changed (we skip processing when already needs_attention)
      assert campaign.notion_failure_count == 3
    end
  end
end
