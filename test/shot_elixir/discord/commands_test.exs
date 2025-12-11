defmodule ShotElixir.Discord.CommandsTest do
  use ShotElixir.DataCase, async: false

  alias ShotElixir.Discord.Commands
  alias ShotElixir.{Accounts, Campaigns, Characters}

  describe "build_whoami_response/1" do
    test "returns link prompt for unlinked Discord user" do
      discord_id = 999_999_999_999_999_999

      response = Commands.build_whoami_response(discord_id)

      assert response =~ "Your Discord account is not linked to Chi War"
      assert response =~ "Use `/link` to generate a link code"
    end

    test "returns profile info for linked user without current campaign" do
      # Create a user with a linked Discord account but no current campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "whoami-test@example.com",
          password: "password123",
          first_name: "Test",
          last_name: "User"
        })

      discord_id = 123_456_789_012_345_678
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      response = Commands.build_whoami_response(discord_id)

      assert response =~ "**Your Chi War Profile**"
      assert response =~ "Name: Test User"
      assert response =~ "Email: whoami-test@example.com"
      assert response =~ "Role: Gamemaster"
      assert response =~ "Current Campaign: None"
      assert response =~ "Characters: None"
    end

    test "returns profile info with current campaign for linked user" do
      # Create a user
      {:ok, user} =
        Accounts.create_user(%{
          email: "whoami-campaign@example.com",
          password: "password123",
          first_name: "Campaign",
          last_name: "Tester"
        })

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          active: true
        })

      # Set user's current campaign
      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      # Link Discord
      discord_id = 234_567_890_123_456_789
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      response = Commands.build_whoami_response(discord_id)

      assert response =~ "**Your Chi War Profile**"
      assert response =~ "Name: Campaign Tester"
      assert response =~ "Current Campaign: Test Campaign"
    end

    test "shows characters from current campaign only" do
      # Create a user
      {:ok, user} =
        Accounts.create_user(%{
          email: "whoami-chars@example.com",
          password: "password123",
          first_name: "Char",
          last_name: "Owner"
        })

      # Create two campaigns
      {:ok, campaign1} =
        Campaigns.create_campaign(%{
          name: "Campaign One",
          user_id: user.id,
          active: true
        })

      {:ok, campaign2} =
        Campaigns.create_campaign(%{
          name: "Campaign Two",
          user_id: user.id,
          active: true
        })

      # Create characters in campaign1
      {:ok, _char1} =
        Characters.create_character(%{
          name: "Alpha Hero",
          campaign_id: campaign1.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      {:ok, _char2} =
        Characters.create_character(%{
          name: "Beta Sidekick",
          campaign_id: campaign1.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      # Create character in campaign2 (should NOT appear)
      {:ok, _char3} =
        Characters.create_character(%{
          name: "Other Campaign Char",
          campaign_id: campaign2.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      # Create an NPC in campaign1 (should NOT appear)
      {:ok, _npc} =
        Characters.create_character(%{
          name: "NPC Villain",
          campaign_id: campaign1.id,
          user_id: user.id,
          action_values: %{"Type" => "NPC"},
          active: true
        })

      # Set user's current campaign to campaign1
      {:ok, user} = Accounts.update_user(user, %{current_campaign_id: campaign1.id})

      # Link Discord
      discord_id = 345_678_901_234_567_890
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      response = Commands.build_whoami_response(discord_id)

      # Should show characters from campaign1
      assert response =~ "Characters:"
      assert response =~ "• Alpha Hero"
      assert response =~ "• Beta Sidekick"

      # Should NOT show character from campaign2 or NPC
      refute response =~ "Other Campaign Char"
      refute response =~ "NPC Villain"
    end

    test "shows player role for non-gamemaster users" do
      # Create a non-gamemaster user
      {:ok, user} =
        Accounts.create_user(%{
          email: "whoami-player@example.com",
          password: "password123",
          first_name: "Player",
          last_name: "Person"
        })

      # Update to non-gamemaster
      {:ok, user} = Accounts.update_user(user, %{gamemaster: false})

      # Link Discord
      discord_id = 456_789_012_345_678_901
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      response = Commands.build_whoami_response(discord_id)

      assert response =~ "Role: Player"
      refute response =~ "Role: Gamemaster"
    end

    test "shows no characters when user has no current campaign" do
      # Create a user with characters but no current campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "whoami-nocamp@example.com",
          password: "password123",
          first_name: "No",
          last_name: "Campaign"
        })

      # Create a campaign (but don't set it as current)
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Orphan Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character in that campaign
      {:ok, _char} =
        Characters.create_character(%{
          name: "Orphan Character",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      # Link Discord (user has no current_campaign_id set)
      discord_id = 567_890_123_456_789_012
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      response = Commands.build_whoami_response(discord_id)

      assert response =~ "Current Campaign: None"
      assert response =~ "Characters: None"
      refute response =~ "Orphan Character"
    end
  end
end
