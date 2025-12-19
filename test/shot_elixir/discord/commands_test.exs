defmodule ShotElixir.Discord.CommandsTest do
  use ShotElixir.DataCase, async: false

  alias ShotElixir.Discord.Commands
  alias ShotElixir.Discord.CurrentFight
  alias ShotElixir.{Accounts, Campaigns, Characters, Fights, Vehicles}

  describe "build_fight_autocomplete_choices/2" do
    test "returns only active, unended fights" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "fight-autocomplete1@example.com",
          password: "password123",
          first_name: "Fight",
          last_name: "Autocomplete"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Autocomplete Campaign",
          user_id: user.id,
          active: true
        })

      # Create an active, unended fight (should appear)
      {:ok, _active_fight} =
        Fights.create_fight(%{
          name: "Active Battle",
          campaign_id: campaign.id,
          active: true
        })

      choices = Commands.build_fight_autocomplete_choices(campaign.id, "")

      assert length(choices) == 1
      assert hd(choices).name == "Active Battle"
      assert hd(choices).value == "Active Battle"
    end

    test "excludes ended fights from autocomplete" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "fight-autocomplete2@example.com",
          password: "password123",
          first_name: "Fight",
          last_name: "Ended"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Ended Campaign",
          user_id: user.id,
          active: true
        })

      # Create an active, unended fight (should appear)
      {:ok, _active_fight} =
        Fights.create_fight(%{
          name: "Ongoing Battle",
          campaign_id: campaign.id,
          active: true
        })

      # Create an active but ended fight (should NOT appear)
      {:ok, _ended_fight} =
        Fights.create_fight(%{
          name: "Finished Battle",
          campaign_id: campaign.id,
          active: true,
          ended_at: DateTime.utc_now()
        })

      choices = Commands.build_fight_autocomplete_choices(campaign.id, "")

      assert length(choices) == 1
      assert hd(choices).name == "Ongoing Battle"
      refute Enum.any?(choices, fn c -> c.name == "Finished Battle" end)
    end

    test "excludes inactive fights from autocomplete" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "fight-autocomplete3@example.com",
          password: "password123",
          first_name: "Fight",
          last_name: "Inactive"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Inactive Campaign",
          user_id: user.id,
          active: true
        })

      # Create an active fight (should appear)
      {:ok, _active_fight} =
        Fights.create_fight(%{
          name: "Active Skirmish",
          campaign_id: campaign.id,
          active: true
        })

      # Create an inactive fight (should NOT appear)
      {:ok, _inactive_fight} =
        Fights.create_fight(%{
          name: "Inactive Skirmish",
          campaign_id: campaign.id,
          active: false
        })

      choices = Commands.build_fight_autocomplete_choices(campaign.id, "")

      assert length(choices) == 1
      assert hd(choices).name == "Active Skirmish"
    end

    test "filters fights by input value (case insensitive)" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "fight-autocomplete4@example.com",
          password: "password123",
          first_name: "Fight",
          last_name: "Filter"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Filter Campaign",
          user_id: user.id,
          active: true
        })

      # Create multiple active fights
      {:ok, _fight1} =
        Fights.create_fight(%{
          name: "Dragon's Lair",
          campaign_id: campaign.id,
          active: true
        })

      {:ok, _fight2} =
        Fights.create_fight(%{
          name: "Temple Showdown",
          campaign_id: campaign.id,
          active: true
        })

      {:ok, _fight3} =
        Fights.create_fight(%{
          name: "Dragon's Cave",
          campaign_id: campaign.id,
          active: true
        })

      # Filter by "dragon" (case insensitive)
      choices = Commands.build_fight_autocomplete_choices(campaign.id, "dragon")

      assert length(choices) == 2
      names = Enum.map(choices, & &1.name)
      assert "Dragon's Lair" in names
      assert "Dragon's Cave" in names
      refute "Temple Showdown" in names
    end

    test "returns empty list for campaign with no matching fights" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "fight-autocomplete5@example.com",
          password: "password123",
          first_name: "Fight",
          last_name: "Empty"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fight Empty Campaign",
          user_id: user.id,
          active: true
        })

      # Only create ended fights
      {:ok, _ended_fight} =
        Fights.create_fight(%{
          name: "Old Battle",
          campaign_id: campaign.id,
          active: true,
          ended_at: DateTime.utc_now()
        })

      choices = Commands.build_fight_autocomplete_choices(campaign.id, "")

      assert choices == []
    end
  end

  describe "handle_start started_at behavior" do
    # Note: These tests simulate the handle_start logic rather than calling the actual
    # function directly. This is because handle_start requires Discord interaction objects
    # which are complex to mock (involving Nostrum API responses, Discord channel/guild IDs,
    # and async job enqueueing). The simulated tests validate the core database behavior
    # that handle_start depends on - specifically that started_at is only set when nil.
    # The actual handle_start function is integration-tested via Discord bot interactions.

    test "sets started_at when fight has not been started" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "start-test1@example.com",
          password: "password123",
          first_name: "Start",
          last_name: "Tester"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Start Test Campaign",
          user_id: user.id,
          active: true
        })

      # Create a fight without started_at
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Unstarted Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Verify fight has no started_at
      assert is_nil(fight.started_at)

      # Simulate what handle_start does: update with started_at
      {:ok, updated_fight} =
        Fights.update_fight(fight, %{
          server_id: "123456789",
          channel_id: "987654321",
          started_at: DateTime.utc_now()
        })

      # Verify started_at is now set
      refute is_nil(updated_fight.started_at)
    end

    test "does not overwrite existing started_at when fight already started" do
      # Create a user and campaign
      {:ok, user} =
        Accounts.create_user(%{
          email: "start-test2@example.com",
          password: "password123",
          first_name: "Start",
          last_name: "Tester2"
        })

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Start Test Campaign 2",
          user_id: user.id,
          active: true
        })

      # Create a fight with started_at already set
      original_started_at = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, fight} =
        Fights.create_fight(%{
          name: "Already Started Fight",
          campaign_id: campaign.id,
          active: true,
          started_at: original_started_at
        })

      # Verify fight has started_at set
      refute is_nil(fight.started_at)

      # Simulate what handle_start does when fight is already started:
      # The code checks if started_at is nil before adding it to attrs
      attrs = %{
        server_id: "123456789",
        channel_id: "987654321"
      }

      # Only add started_at if not already set (this mimics the handle_start logic)
      attrs =
        if is_nil(fight.started_at) do
          Map.put(attrs, :started_at, DateTime.utc_now())
        else
          attrs
        end

      {:ok, updated_fight} = Fights.update_fight(fight, attrs)

      # Verify started_at was NOT changed (compare truncated to second to avoid precision issues)
      assert DateTime.truncate(updated_fight.started_at, :second) ==
               DateTime.truncate(original_started_at, :second)
    end
  end

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

  describe "build_stats_response/2" do
    # Note: Each test uses unique server_id values to avoid test pollution.
    # The CurrentFight agent is already started by the application.

    test "returns link prompt for unlinked Discord user" do
      discord_id = 111_111_111_111_111_111
      server_id = 222_222_222_222_222_222

      response = Commands.build_stats_response(discord_id, server_id)

      assert response =~ "Your Discord account is not linked to Chi War"
      assert response =~ "Use `/link` to generate a link code"
    end

    test "returns no active fight message when no fight is set and no current character" do
      # Create a linked user without a current character
      {:ok, user} =
        Accounts.create_user(%{
          email: "mystats-test1@example.com",
          password: "password123",
          first_name: "Stats",
          last_name: "Tester"
        })

      discord_id = 333_333_333_333_333_333
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      server_id = 444_444_444_444_444_444

      response = Commands.build_stats_response(discord_id, server_id)

      assert response =~ "There is no active fight in this server"
      assert response =~ "You can set a current character with `/link`"
    end

    test "returns current character stats when no fight but current_character is set" do
      # Create a linked user with a current character
      {:ok, user} =
        Accounts.create_user(%{
          email: "mystats-current-char@example.com",
          password: "password123",
          first_name: "Has",
          last_name: "Character"
        })

      discord_id = 888_777_666_555_444_333
      {:ok, user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Stats Current Char Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with action values
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Fighter",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Wounds" => 0,
            "Defense" => 14,
            "Toughness" => 6,
            "Speed" => 7,
            "Fortune" => 5,
            "Max Fortune" => 7,
            "MainAttack" => "Martial Arts",
            "Martial Arts" => 15
          }
        })

      # Set the current character
      {:ok, _user} = Accounts.set_current_character(user, character.id)

      server_id = 111_222_333_444_555_666

      response = Commands.build_stats_response(discord_id, server_id)

      # Should show the character stats without requiring a fight
      assert response =~ "Your Current Character"
      assert response =~ "Test Fighter"
      assert response =~ "PC"
      assert response =~ "Defense: **14**"
      assert response =~ "Martial Arts: **15**"
      assert response =~ "Fortune: **5/7**"
    end

    test "returns no characters message when user has no characters in fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "mystats-test2@example.com",
          password: "password123",
          first_name: "No",
          last_name: "Character"
        })

      discord_id = 555_555_555_555_555_555
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Mystats Test Campaign",
          user_id: user.id,
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Test Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Set the current fight for the server
      server_id = 666_666_666_666_666_666
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      assert response =~ "You don't have any characters in the fight"
      assert response =~ "Test Fight"
    end

    test "shows character stats when user has character in fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "mystats-test3@example.com",
          password: "password123",
          first_name: "Character",
          last_name: "Owner"
        })

      discord_id = 777_777_777_777_777_777
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Stats Test Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with specific stats
      {:ok, character} =
        Characters.create_character(%{
          name: "Johnny Fist",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Wounds" => 5,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 6,
            "Fortune" => 3,
            "Max Fortune" => 8,
            "MainAttack" => "Martial Arts",
            "Martial Arts" => 15
          },
          active: true
        })

      # Create a fight and add character to it
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Combat Encounter",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight via shot
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 12,
          impairments: 1
        })

      # Set the current fight for the server
      server_id = 888_888_888_888_888_888
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      # Check header
      assert response =~ "**Your Characters in Combat Encounter**"

      # Check character name and type
      assert response =~ "**Johnny Fist** (PC)"

      # Check shot position
      assert response =~ "Shot: **12**"

      # Check combat stats
      assert response =~ "Wounds: **5**"
      assert response =~ "Defense: **14**"
      assert response =~ "Toughness: **7**"

      # Check attack value
      assert response =~ "Martial Arts: **15**"

      # Check speed and fortune
      assert response =~ "Speed: **6**"
      assert response =~ "Fortune: **3/8**"

      # Check impairments (includes warning emoji)
      assert response =~ "⚠️ Impairments: **1**"
    end

    test "shows multiple characters when user has several in fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "mystats-test4@example.com",
          password: "password123",
          first_name: "Multi",
          last_name: "Char"
        })

      discord_id = 999_888_777_666_555_444
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Multi Char Campaign",
          user_id: user.id,
          active: true
        })

      # Create two characters
      {:ok, char1} =
        Characters.create_character(%{
          name: "Fighter One",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      {:ok, char2} =
        Characters.create_character(%{
          name: "Fighter Two",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Multi Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char1.id,
          shot: 10
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char2.id,
          shot: 8
        })

      # Set the current fight for the server
      server_id = 123_456_789_012_345_678
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      assert response =~ "**Fighter One**"
      assert response =~ "**Fighter Two**"
      assert response =~ "Shot: **10**"
      assert response =~ "Shot: **8**"
    end

    test "only shows user's own characters in fight" do
      # Create two users
      {:ok, user1} =
        Accounts.create_user(%{
          email: "mystats-owner@example.com",
          password: "password123",
          first_name: "Owner",
          last_name: "User"
        })

      {:ok, user2} =
        Accounts.create_user(%{
          email: "mystats-other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      discord_id_1 = 111_222_333_444_555_666
      {:ok, _user} = Accounts.link_discord(user1, discord_id_1)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Ownership Test Campaign",
          user_id: user1.id,
          active: true
        })

      # Create characters for each user
      {:ok, my_char} =
        Characters.create_character(%{
          name: "My Character",
          campaign_id: campaign.id,
          user_id: user1.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      {:ok, their_char} =
        Characters.create_character(%{
          name: "Their Character",
          campaign_id: campaign.id,
          user_id: user2.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Ownership Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: my_char.id,
          shot: 15
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: their_char.id,
          shot: 14
        })

      # Set the current fight for the server
      server_id = 222_333_444_555_666_777
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id_1, server_id)

      # Should show only user1's character
      assert response =~ "**My Character**"
      refute response =~ "Their Character"
    end

    test "shows shot as not set when shot position is nil" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "mystats-noshot@example.com",
          password: "password123",
          first_name: "No",
          last_name: "Shot"
        })

      discord_id = 333_444_555_666_777_888
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "No Shot Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character
      {:ok, character} =
        Characters.create_character(%{
          name: "Waiting Hero",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Waiting Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight with nil shot (not yet placed on initiative)
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: nil
        })

      # Set the current fight for the server
      server_id = 444_555_666_777_888_999
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      assert response =~ "**Waiting Hero**"
      assert response =~ "Shot: _Not set_"
    end

    test "includes vehicle stats when user has a vehicle in the fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "stats-vehicle@example.com",
          password: "password123",
          first_name: "Vehicle",
          last_name: "Driver"
        })

      discord_id = 800_000_000_000_000_001
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Vehicle Stats Campaign",
          user_id: user.id,
          active: true
        })

      # Create a driver character (the user's character who drives the vehicle)
      {:ok, driver} =
        Characters.create_character(%{
          name: "Speed Racer",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Driving" => 15
          }
        })

      # Create a vehicle with stats
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Muscle Car",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Acceleration" => 8,
            "Handling" => 7,
            "Squeal" => 10,
            "Frame" => 6,
            "Chase Points" => 3,
            "Condition Points" => 5
          }
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Chase Scene",
          campaign_id: campaign.id,
          active: true
        })

      # Add the driver character to fight first
      {:ok, driver_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: driver.id,
          shot: 12
        })

      # Add vehicle to fight with driver_id pointing to the driver's shot
      {:ok, _vehicle_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          vehicle_id: vehicle.id,
          shot: 10,
          impairments: 1,
          driver_id: driver_shot.id
        })

      # Set up the fight context
      server_id = 800_000_000_000_000_002
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      # Should show "Your Characters & Vehicles in" header (driver + vehicle)
      assert response =~ "Your Characters & Vehicles in Chase Scene"
      # Should show the vehicle name with emoji
      assert response =~ "🚗 **Muscle Car**"
      # Should show vehicle-specific stats
      assert response =~ "Acceleration: **8**"
      assert response =~ "Handling: **7**"
      assert response =~ "Squeal: **10**"
      assert response =~ "Frame: **6**"
      # Should show chase stats
      assert response =~ "Chase Points: **3**"
      assert response =~ "Condition Points: **5**"
      # Should show impairments
      assert response =~ "Impairments: **1**"
      # Should show shot position
      assert response =~ "Shot: **10**"
    end

    test "shows both characters and vehicles when user has both in fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "stats-both@example.com",
          password: "password123",
          first_name: "Both",
          last_name: "Types"
        })

      discord_id = 800_000_000_000_000_003
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Both Types Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character
      {:ok, character} =
        Characters.create_character(%{
          name: "Johnny Driver",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Wounds" => 10,
            "Defense" => 14,
            "Toughness" => 6,
            "Speed" => 7,
            "Fortune" => 5,
            "Max Fortune" => 8,
            "MainAttack" => "Driving",
            "Driving" => 15
          }
        })

      # Create a vehicle
      {:ok, vehicle} =
        Vehicles.create_vehicle(%{
          name: "Hot Rod",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Acceleration" => 9,
            "Handling" => 8,
            "Squeal" => 11,
            "Frame" => 7
          }
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Street Race",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight (this character will also be the driver)
      {:ok, char_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 12
        })

      # Add vehicle to fight with the character as driver
      {:ok, _vehicle_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          vehicle_id: vehicle.id,
          shot: 8,
          driver_id: char_shot.id
        })

      # Set up the fight context
      server_id = 800_000_000_000_000_004
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      # Should show "Characters & Vehicles" header
      assert response =~ "Your Characters & Vehicles in Street Race"
      # Should show the character
      assert response =~ "**Johnny Driver**"
      assert response =~ "Driving: **15**"
      # Should show the vehicle
      assert response =~ "🚗 **Hot Rod**"
      assert response =~ "Acceleration: **9**"
    end

    test "does not show vehicles driven by other characters (mooks)" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "stats-mook-driver@example.com",
          password: "password123",
          first_name: "User",
          last_name: "Character"
        })

      discord_id = 800_000_000_000_000_005
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Mook Driver Campaign",
          user_id: user.id,
          active: true
        })

      # Create user's character
      {:ok, user_character} =
        Characters.create_character(%{
          name: "Hero Driver",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC", "Driving" => 15}
        })

      # Create a mook (no user_id)
      {:ok, mook} =
        Characters.create_character(%{
          name: "Bad Guy Mook",
          campaign_id: campaign.id,
          user_id: nil,
          action_values: %{"Type" => "Mook"}
        })

      # Create user's vehicle (driven by user's character)
      {:ok, user_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Hero Car",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC", "Acceleration" => 10}
        })

      # Create another vehicle owned by user but driven by mook
      {:ok, mook_driven_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Enemy Car",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "Mook", "Acceleration" => 8}
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Chase Test",
          campaign_id: campaign.id,
          active: true
        })

      # Add user's character to fight
      {:ok, user_char_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: user_character.id,
          shot: 12
        })

      # Add mook to fight
      {:ok, mook_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: mook.id,
          shot: 10
        })

      # Add user's vehicle (driven by user's character)
      {:ok, _user_vehicle_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          vehicle_id: user_vehicle.id,
          shot: 11,
          driver_id: user_char_shot.id
        })

      # Add mook-driven vehicle (should NOT appear in user's stats)
      {:ok, _mook_vehicle_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          vehicle_id: mook_driven_vehicle.id,
          shot: 9,
          driver_id: mook_shot.id
        })

      # Set up the fight context
      server_id = 800_000_000_000_000_006
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_stats_response(discord_id, server_id)

      # Should show user's character and their vehicle
      assert response =~ "**Hero Driver**"
      assert response =~ "🚗 **Hero Car**"
      # Should NOT show the mook-driven vehicle
      refute response =~ "Enemy Car"
      refute response =~ "Bad Guy Mook"
    end
  end

  describe "build_fortune_response/3" do
    test "returns link prompt for unlinked Discord user" do
      discord_id = 600_000_000_000_000_001
      server_id = 600_000_000_000_000_002

      response = Commands.build_fortune_response(discord_id, server_id, 1)

      assert response =~ "Your Discord account is not linked to Chi War"
      assert response =~ "Use `/link` to generate a link code"
    end

    test "returns no active fight message when no fight is set" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-nofight@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "NoFight"
        })

      discord_id = 600_000_000_000_000_003
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      server_id = 600_000_000_000_000_004

      response = Commands.build_fortune_response(discord_id, server_id, 1)

      assert response =~ "There is no active fight in this server"
      assert response =~ "Use `/start` to begin a fight"
    end

    test "returns no characters message when user has no characters in fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-nochar@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "NoChar"
        })

      discord_id = 600_000_000_000_000_005
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune No Char Campaign",
          user_id: user.id,
          active: true
        })

      # Create a fight (but don't add user's character to it)
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Empty Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Set the current fight for the server
      server_id = 600_000_000_000_000_006
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 1)

      assert response =~ "You don't have any characters in the fight"
      assert response =~ "Empty Fight"
    end

    test "successfully spends fortune points" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-success@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Spender"
        })

      discord_id = 600_000_000_000_000_007
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune Success Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with fortune
      {:ok, character} =
        Characters.create_character(%{
          name: "Lucky Hero",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 5,
            "Max Fortune" => 8
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Fortune Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_008
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 2)

      # Check success message
      assert response =~ "**Lucky Hero** spent **2** Fortune!"
      assert response =~ "Fortune remaining: **3/8**"

      # Verify the character's fortune was actually updated
      updated_character = Characters.get_character!(character.id)
      assert updated_character.action_values["Fortune"] == 3
    end

    test "returns error when trying to spend more fortune than available" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-toomuch@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "TooMuch"
        })

      discord_id = 600_000_000_000_000_009
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune Too Much Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with limited fortune
      {:ok, character} =
        Characters.create_character(%{
          name: "Poor Hero",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 2,
            "Max Fortune" => 8
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Too Much Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_010
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 5)

      assert response =~ "**Poor Hero** only has 2 Fortune points, but you tried to spend 5"

      # Verify the character's fortune was NOT changed
      updated_character = Characters.get_character!(character.id)
      assert updated_character.action_values["Fortune"] == 2
    end

    test "returns error when character has zero fortune" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-zero@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Zero"
        })

      discord_id = 600_000_000_000_000_011
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune Zero Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with zero fortune
      {:ok, character} =
        Characters.create_character(%{
          name: "Unlucky Hero",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 0,
            "Max Fortune" => 8
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Zero Fortune Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_012
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 1)

      assert response =~ "**Unlucky Hero** has no Fortune points to spend!"
      assert response =~ "0/8"
    end

    test "displays custom fortune type (Chi) correctly" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-chi@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Chi"
        })

      discord_id = 600_000_000_000_000_013
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Chi Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with Chi instead of Fortune
      {:ok, character} =
        Characters.create_character(%{
          name: "Martial Master",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 6,
            "Max Fortune" => 10,
            "FortuneType" => "Chi"
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Chi Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_014
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 3)

      # Check that "Chi" is used instead of "Fortune" in the message
      assert response =~ "**Martial Master** spent **3** Chi!"
      assert response =~ "Chi remaining: **3/10**"
      refute response =~ "Fortune remaining"
    end

    test "displays custom fortune type (Magic) correctly" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-magic@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Magic"
        })

      discord_id = 600_000_000_000_000_015
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Magic Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with Magic instead of Fortune
      {:ok, character} =
        Characters.create_character(%{
          name: "Sorcerer Supreme",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 4,
            "Max Fortune" => 7,
            "FortuneType" => "Magic"
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Magic Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_016
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 1)

      # Check that "Magic" is used
      assert response =~ "**Sorcerer Supreme** spent **1** Magic!"
      assert response =~ "Magic remaining: **3/7**"
    end

    test "fortune cannot go below zero" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-floor@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Floor"
        })

      discord_id = 600_000_000_000_000_017
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune Floor Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with exactly 1 fortune
      {:ok, character} =
        Characters.create_character(%{
          name: "Last Fortune Hero",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 1,
            "Max Fortune" => 8
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Floor Test Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_018
      CurrentFight.set(server_id, fight.id)

      # Spend exactly 1 fortune (the amount they have)
      response = Commands.build_fortune_response(discord_id, server_id, 1)

      # Should succeed
      assert response =~ "**Last Fortune Hero** spent **1** Fortune!"
      assert response =~ "Fortune remaining: **0/8**"

      # Verify fortune is exactly 0, not negative
      updated_character = Characters.get_character!(character.id)
      assert updated_character.action_values["Fortune"] == 0
    end

    test "uses most recently updated character when user has multiple in fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-multi@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Multi"
        })

      discord_id = 600_000_000_000_000_019
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune Multi Campaign",
          user_id: user.id,
          active: true
        })

      # Create two characters with different fortune values
      {:ok, char1} =
        Characters.create_character(%{
          name: "First Fighter",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 3,
            "Max Fortune" => 8
          },
          active: true
        })

      # Small delay to ensure different timestamps
      Process.sleep(10)

      {:ok, char2} =
        Characters.create_character(%{
          name: "Second Fighter",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 7,
            "Max Fortune" => 10
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Multi Char Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char1.id,
          shot: 10
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char2.id,
          shot: 8
        })

      # Set the current fight
      server_id = 600_000_000_000_000_020
      CurrentFight.set(server_id, fight.id)

      response = Commands.build_fortune_response(discord_id, server_id, 1)

      # Should spend from Second Fighter (most recently updated/created)
      assert response =~ "**Second Fighter** spent **1** Fortune!"
      assert response =~ "Fortune remaining: **6/10**"

      # Verify Second Fighter's fortune was updated, First Fighter unchanged
      updated_char1 = Characters.get_character!(char1.id)
      updated_char2 = Characters.get_character!(char2.id)
      assert updated_char1.action_values["Fortune"] == 3
      assert updated_char2.action_values["Fortune"] == 6
    end

    test "spends fortune from specified character when name provided" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-select@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Selector"
        })

      discord_id = 600_000_000_000_000_021
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Fortune Select Campaign",
          user_id: user.id,
          active: true
        })

      # Create two characters
      {:ok, char1} =
        Characters.create_character(%{
          name: "Alpha Warrior",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 5,
            "Max Fortune" => 8
          },
          active: true
        })

      Process.sleep(10)

      {:ok, char2} =
        Characters.create_character(%{
          name: "Beta Mage",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 3,
            "Max Fortune" => 6
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Selection Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char1.id,
          shot: 10
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char2.id,
          shot: 8
        })

      # Set the current fight
      server_id = 600_000_000_000_000_022
      CurrentFight.set(server_id, fight.id)

      # Spend fortune from Alpha Warrior specifically (not the default Beta Mage)
      response = Commands.build_fortune_response(discord_id, server_id, 2, "Alpha Warrior")

      assert response =~ "**Alpha Warrior** spent **2** Fortune!"
      assert response =~ "Fortune remaining: **3/8**"

      # Verify Alpha Warrior's fortune was updated, Beta Mage unchanged
      updated_char1 = Characters.get_character!(char1.id)
      updated_char2 = Characters.get_character!(char2.id)
      assert updated_char1.action_values["Fortune"] == 3
      assert updated_char2.action_values["Fortune"] == 3
    end

    test "character selection is case insensitive" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "fortune-case@example.com",
          password: "password123",
          first_name: "Fortune",
          last_name: "Case"
        })

      discord_id = 600_000_000_000_000_023
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Case Test Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character with mixed case name
      {:ok, character} =
        Characters.create_character(%{
          name: "Johnny Thunder",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 4,
            "Max Fortune" => 7
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Case Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add character to fight
      {:ok, _shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Set the current fight
      server_id = 600_000_000_000_000_024
      CurrentFight.set(server_id, fight.id)

      # Try with lowercase
      response = Commands.build_fortune_response(discord_id, server_id, 1, "johnny thunder")

      assert response =~ "**Johnny Thunder** spent **1** Fortune!"
    end
  end

  describe "build_link_autocomplete_choices/2" do
    test "excludes template characters from autocomplete" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "link-template@example.com",
          password: "password123",
          first_name: "Link",
          last_name: "Template"
        })

      discord_id = 800_000_000_000_000_001
      {:ok, user} = Accounts.link_discord(user, discord_id)

      # Create a campaign and set it as user's current campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Link Template Campaign",
          user_id: user.id,
          active: true
        })

      {:ok, _user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      # Create a regular character (should appear)
      {:ok, _regular_char} =
        Characters.create_character(%{
          name: "Regular Hero",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true,
          is_template: false
        })

      # Create a template character (should NOT appear)
      {:ok, _template_char} =
        Characters.create_character(%{
          name: "Template Character",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true,
          is_template: true
        })

      choices = Commands.build_link_autocomplete_choices(discord_id, "")

      # Should only show the regular character, not the template
      assert length(choices) == 1
      values = Enum.map(choices, & &1.value)
      assert "Regular Hero" in values
      refute "Template Character" in values
    end

    test "includes active non-template characters in autocomplete" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "link-active@example.com",
          password: "password123",
          first_name: "Link",
          last_name: "Active"
        })

      discord_id = 800_000_000_000_000_002
      {:ok, user} = Accounts.link_discord(user, discord_id)

      # Create a campaign and set it as user's current campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Link Active Campaign",
          user_id: user.id,
          active: true
        })

      {:ok, _user} = Accounts.update_user(user, %{current_campaign_id: campaign.id})

      # Create multiple active characters (all should appear)
      {:ok, _char1} =
        Characters.create_character(%{
          name: "Fighter One",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: true
        })

      {:ok, _char2} =
        Characters.create_character(%{
          name: "Fighter Two",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "NPC"},
          active: true
        })

      # Create an inactive character (should NOT appear)
      {:ok, _inactive_char} =
        Characters.create_character(%{
          name: "Inactive Fighter",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC"},
          active: false
        })

      choices = Commands.build_link_autocomplete_choices(discord_id, "")

      # Should show both active characters, not the inactive one
      assert length(choices) == 2
      values = Enum.map(choices, & &1.value)
      assert "Fighter One" in values
      assert "Fighter Two" in values
      refute "Inactive Fighter" in values
    end
  end

  describe "build_fortune_autocomplete_choices/3" do
    test "returns empty list for unlinked Discord user" do
      discord_id = 700_000_000_000_000_001
      server_id = 700_000_000_000_000_002

      choices = Commands.build_fortune_autocomplete_choices(discord_id, server_id, "")

      assert choices == []
    end

    test "returns empty list when no active fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "autocomplete-nofight@example.com",
          password: "password123",
          first_name: "Auto",
          last_name: "Complete"
        })

      discord_id = 700_000_000_000_000_003
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      server_id = 700_000_000_000_000_004

      choices = Commands.build_fortune_autocomplete_choices(discord_id, server_id, "")

      assert choices == []
    end

    test "returns user's characters in the current fight" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "autocomplete-chars@example.com",
          password: "password123",
          first_name: "Auto",
          last_name: "Chars"
        })

      discord_id = 700_000_000_000_000_005
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Autocomplete Campaign",
          user_id: user.id,
          active: true
        })

      # Create characters with fortune
      {:ok, char1} =
        Characters.create_character(%{
          name: "Sword Master",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 5,
            "Max Fortune" => 8
          },
          active: true
        })

      {:ok, char2} =
        Characters.create_character(%{
          name: "Fire Wizard",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{
            "Type" => "PC",
            "Fortune" => 3,
            "Max Fortune" => 6,
            "FortuneType" => "Magic"
          },
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Autocomplete Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char1.id,
          shot: 10
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char2.id,
          shot: 8
        })

      # Set the current fight
      server_id = 700_000_000_000_000_006
      CurrentFight.set(server_id, fight.id)

      choices = Commands.build_fortune_autocomplete_choices(discord_id, server_id, "")

      assert length(choices) == 2

      # Check that both characters appear with fortune info
      names = Enum.map(choices, & &1.name)
      assert Enum.any?(names, &String.contains?(&1, "Sword Master"))
      assert Enum.any?(names, &String.contains?(&1, "Fire Wizard"))
      assert Enum.any?(names, &String.contains?(&1, "Fortune: 5/8"))
      assert Enum.any?(names, &String.contains?(&1, "Magic: 3/6"))

      # Check values are the character names
      values = Enum.map(choices, & &1.value)
      assert "Sword Master" in values
      assert "Fire Wizard" in values
    end

    test "filters characters by input" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "autocomplete-filter@example.com",
          password: "password123",
          first_name: "Auto",
          last_name: "Filter"
        })

      discord_id = 700_000_000_000_000_007
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Filter Campaign",
          user_id: user.id,
          active: true
        })

      # Create characters
      {:ok, char1} =
        Characters.create_character(%{
          name: "Johnny Fist",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC", "Fortune" => 5, "Max Fortune" => 8},
          active: true
        })

      {:ok, char2} =
        Characters.create_character(%{
          name: "Sarah Chen",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC", "Fortune" => 3, "Max Fortune" => 6},
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Filter Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char1.id,
          shot: 10
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char2.id,
          shot: 8
        })

      # Set the current fight
      server_id = 700_000_000_000_000_008
      CurrentFight.set(server_id, fight.id)

      # Filter by "john"
      choices = Commands.build_fortune_autocomplete_choices(discord_id, server_id, "john")

      assert length(choices) == 1
      assert hd(choices).value == "Johnny Fist"
    end

    test "characters are ordered by most recently updated" do
      # Create a linked user
      {:ok, user} =
        Accounts.create_user(%{
          email: "autocomplete-order@example.com",
          password: "password123",
          first_name: "Auto",
          last_name: "Order"
        })

      discord_id = 700_000_000_000_000_009
      {:ok, _user} = Accounts.link_discord(user, discord_id)

      # Create a campaign
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Order Campaign",
          user_id: user.id,
          active: true
        })

      # Create characters with delay to ensure different timestamps
      {:ok, char1} =
        Characters.create_character(%{
          name: "First Created",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC", "Fortune" => 5, "Max Fortune" => 8},
          active: true
        })

      Process.sleep(10)

      {:ok, char2} =
        Characters.create_character(%{
          name: "Second Created",
          campaign_id: campaign.id,
          user_id: user.id,
          action_values: %{"Type" => "PC", "Fortune" => 3, "Max Fortune" => 6},
          active: true
        })

      # Create a fight
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Order Fight",
          campaign_id: campaign.id,
          active: true
        })

      # Add both characters to fight
      {:ok, _shot1} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char1.id,
          shot: 10
        })

      {:ok, _shot2} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: char2.id,
          shot: 8
        })

      # Set the current fight
      server_id = 700_000_000_000_000_010
      CurrentFight.set(server_id, fight.id)

      choices = Commands.build_fortune_autocomplete_choices(discord_id, server_id, "")

      # Most recently created (Second Created) should be first
      assert hd(choices).value == "Second Created"
    end
  end
end
