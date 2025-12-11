defmodule ShotElixir.Discord.ServerSettingsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Discord.ServerSettings
  alias ShotElixir.Discord.CurrentCampaign
  alias ShotElixir.Discord.CurrentFight
  alias ShotElixir.Campaigns
  alias ShotElixir.Fights
  alias ShotElixir.Accounts

  # Use large integers for Discord server IDs (snowflake format)
  @server_id_1 111_111_111_111_111_111
  @server_id_2 222_222_222_222_222_222
  @server_id_3 333_333_333_333_333_333

  setup do
    # Clear agent caches before each test
    CurrentCampaign.clear_all_cache()
    CurrentFight.clear_all_cache()

    # Create a test user
    {:ok, user} =
      Accounts.create_user(%{
        email: "discord-settings-test@example.com",
        password: "password123",
        first_name: "Discord",
        last_name: "Tester"
      })

    {:ok, user: user}
  end

  describe "get_or_create_settings/1" do
    test "creates new settings record for unknown server" do
      setting = ServerSettings.get_or_create_settings(@server_id_1)

      assert setting.server_id == @server_id_1
      assert setting.current_campaign_id == nil
      assert setting.current_fight_id == nil
      assert setting.settings == %{}
    end

    test "returns existing settings for known server" do
      # Create initial settings
      first = ServerSettings.get_or_create_settings(@server_id_2)

      # Get again
      second = ServerSettings.get_or_create_settings(@server_id_2)

      assert first.id == second.id
      assert second.server_id == @server_id_2
    end

    test "handles multiple servers independently" do
      setting1 = ServerSettings.get_or_create_settings(@server_id_1)
      setting2 = ServerSettings.get_or_create_settings(@server_id_2)

      assert setting1.id != setting2.id
      assert setting1.server_id == @server_id_1
      assert setting2.server_id == @server_id_2
    end
  end

  describe "current campaign" do
    setup %{user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Discord Test Campaign",
          user_id: user.id,
          active: true
        })

      {:ok, campaign: campaign}
    end

    test "set and get current campaign", %{campaign: campaign} do
      {:ok, _} = ServerSettings.set_current_campaign(@server_id_1, campaign.id)

      result = ServerSettings.get_current_campaign(@server_id_1)

      assert result.id == campaign.id
      assert result.name == "Discord Test Campaign"
    end

    test "get current campaign ID", %{campaign: campaign} do
      {:ok, _} = ServerSettings.set_current_campaign(@server_id_1, campaign.id)

      result = ServerSettings.get_current_campaign_id(@server_id_1)

      assert result == campaign.id
    end

    test "returns nil when no campaign set" do
      assert ServerSettings.get_current_campaign(@server_id_3) == nil
      assert ServerSettings.get_current_campaign_id(@server_id_3) == nil
    end

    test "clear current campaign", %{campaign: campaign} do
      # First set a campaign, then clear it
      {:ok, _} = ServerSettings.set_current_campaign(@server_id_1, campaign.id)
      {:ok, _} = ServerSettings.set_current_campaign(@server_id_1, nil)

      assert ServerSettings.get_current_campaign(@server_id_1) == nil
    end
  end

  describe "current fight" do
    setup %{user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Campaign",
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id,
          active: true
        })

      {:ok, campaign: campaign, fight: fight}
    end

    test "set and get current fight", %{fight: fight} do
      {:ok, _} = ServerSettings.set_current_fight(@server_id_1, fight.id)

      assert ServerSettings.get_current_fight_id(@server_id_1) == fight.id
    end

    test "get current fight struct", %{fight: fight} do
      {:ok, _} = ServerSettings.set_current_fight(@server_id_1, fight.id)

      result = ServerSettings.get_current_fight(@server_id_1)

      assert result.id == fight.id
      assert result.name == "Test Fight"
    end

    test "returns nil when no fight set" do
      assert ServerSettings.get_current_fight_id(@server_id_3) == nil
      assert ServerSettings.get_current_fight(@server_id_3) == nil
    end

    test "clear current fight", %{fight: fight} do
      {:ok, _} = ServerSettings.set_current_fight(@server_id_1, fight.id)
      {:ok, _} = ServerSettings.set_current_fight(@server_id_1, nil)

      assert ServerSettings.get_current_fight_id(@server_id_1) == nil
    end
  end

  describe "custom settings" do
    test "set and get custom setting" do
      {:ok, _} = ServerSettings.set_custom_setting(@server_id_1, "notification_channel", "12345")

      assert ServerSettings.get_custom_setting(@server_id_1, "notification_channel") == "12345"
    end

    test "returns nil for unset custom setting" do
      assert ServerSettings.get_custom_setting(@server_id_3, "nonexistent") == nil
    end

    test "multiple custom settings" do
      {:ok, _} = ServerSettings.set_custom_setting(@server_id_1, "key1", "value1")
      {:ok, _} = ServerSettings.set_custom_setting(@server_id_1, "key2", "value2")

      assert ServerSettings.get_custom_setting(@server_id_1, "key1") == "value1"
      assert ServerSettings.get_custom_setting(@server_id_1, "key2") == "value2"
    end
  end

  describe "list_all/0" do
    test "returns all server settings", %{user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "List Test Campaign",
          user_id: user.id
        })

      ServerSettings.get_or_create_settings(@server_id_1)
      {:ok, _} = ServerSettings.set_current_campaign(@server_id_2, campaign.id)

      all = ServerSettings.list_all()

      assert length(all) >= 2
      server_ids = Enum.map(all, & &1.server_id)
      assert @server_id_1 in server_ids
      assert @server_id_2 in server_ids
    end
  end

  describe "CurrentCampaign agent integration" do
    setup %{user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Agent Test Campaign",
          user_id: user.id,
          active: true
        })

      {:ok, campaign: campaign}
    end

    test "set via agent persists to database", %{campaign: campaign} do
      CurrentCampaign.set(@server_id_1, campaign.id)

      # Clear cache to force DB read
      CurrentCampaign.clear_cache(@server_id_1)

      # Should still get campaign from database
      result = CurrentCampaign.get(@server_id_1)
      assert result.id == campaign.id
    end

    test "settings persist after cache clear (simulating restart)", %{campaign: campaign} do
      CurrentCampaign.set(@server_id_1, campaign.id)

      # Simulate restart by clearing all cache
      CurrentCampaign.clear_all_cache()

      # Should load from database
      result = CurrentCampaign.get(@server_id_1)
      assert result.id == campaign.id
    end

    test "get caches the value", %{campaign: campaign} do
      # Set via database directly
      {:ok, _} = ServerSettings.set_current_campaign(@server_id_1, campaign.id)

      # First get loads from DB
      result1 = CurrentCampaign.get(@server_id_1)
      assert result1.id == campaign.id

      # Verify it's now cached (agent state contains the value)
      # Second get should use cache (no way to directly verify, but coverage)
      result2 = CurrentCampaign.get(@server_id_1)
      assert result2.id == campaign.id
    end
  end

  describe "CurrentFight agent integration" do
    setup %{user: user} do
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Agent Campaign",
          user_id: user.id
        })

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Agent Test Fight",
          campaign_id: campaign.id,
          active: true
        })

      {:ok, fight: fight}
    end

    test "set via agent persists to database", %{fight: fight} do
      CurrentFight.set(@server_id_1, fight.id)

      # Clear cache to force DB read
      CurrentFight.clear_cache(@server_id_1)

      # Should still get fight from database
      result = CurrentFight.get(@server_id_1)
      assert result == fight.id
    end

    test "settings persist after cache clear (simulating restart)", %{fight: fight} do
      CurrentFight.set(@server_id_1, fight.id)

      # Simulate restart
      CurrentFight.clear_all_cache()

      # Should load from database
      result = CurrentFight.get(@server_id_1)
      assert result == fight.id
    end
  end
end
