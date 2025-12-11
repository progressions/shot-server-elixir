defmodule ShotElixir.Discord.CommandsTest do
  use ShotElixir.DataCase, async: false

  alias ShotElixir.Discord.Commands
  alias ShotElixir.Discord.CurrentFight
  alias ShotElixir.{Accounts, Campaigns, Characters, Fights}

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

    test "returns no active fight message when no fight is set" do
      # Create a linked user
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
      assert response =~ "Use `/start` to begin a fight"
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
  end
end
