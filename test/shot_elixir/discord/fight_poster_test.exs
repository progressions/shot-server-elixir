defmodule ShotElixir.Discord.FightPosterTest do
  @moduledoc """
  Tests for FightPoster output.

  The expected output strings include trailing spaces after character names
  to match the Rails FightPoster output exactly.
  """
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Discord.FightPoster
  alias ShotElixir.{Accounts, Campaigns, Characters, Vehicles, Fights}
  alias ShotElixir.Fights.{Shot, FightEvent}
  alias ShotElixir.Effects.{Effect, CharacterEffect}
  alias ShotElixir.Repo

  setup do
    # Create user
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    # Create campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Action Movie",
        description: "Test campaign",
        user_id: user.id
      })

    %{user: user, campaign: campaign}
  end

  describe "with no shots or characters" do
    test "shows fight with description", %{campaign: campaign} do
      # Create fight with description containing mention markup
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          description:
            "The Christening of the [@Immortal Woman](/sites/72f84df7-6dfc-42f3-8d55-dba8e40d3190), featuring [@Huan Ken](/characters/2bb9d3d6-3255-4d81-b7c4-64b17b95bbc5), King of the [@Thunder Pagoda](/factions/d9bc6c2f-ebe1-4300-a836-dcb36e6454ab)",
          campaign_id: campaign.id,
          sequence: 1
        })

      # Create fight event
      %FightEvent{}
      |> FightEvent.changeset(%{
        event_type: "fight_started",
        description: "Fight started",
        fight_id: fight.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      # Note: trailing space after name lines matches Rails output
      expected =
        "# Museum Battle\n" <>
          "The Christening of the Immortal Woman, featuring Huan Ken, King of the Thunder Pagoda\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "\n" <>
          "Fight started\n"

      assert result == expected
    end
  end

  describe "with HTML in the description" do
    test "converts HTML to markdown", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          description: "<p>Fight to recover the <strong>artifact</strong></p>",
          campaign_id: campaign.id,
          sequence: 1
        })

      %FightEvent{}
      |> FightEvent.changeset(%{
        event_type: "fight_started",
        description: "Fight started",
        fight_id: fight.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      expected =
        "# Museum Battle\n" <>
          "Fight to recover the **artifact**\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "\n" <>
          "Fight started\n"

      assert result == expected
    end
  end

  describe "with one character" do
    test "shows character stats", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          description:
            "The Christening of the [@Immortal Woman](/sites/72f84df7-6dfc-42f3-8d55-dba8e40d3190), featuring [@Huan Ken](/characters/2bb9d3d6-3255-4d81-b7c4-64b17b95bbc5), King of the [@Thunder Pagoda](/factions/d9bc6c2f-ebe1-4300-a836-dcb36e6454ab)",
          campaign_id: campaign.id,
          sequence: 1
        })

      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "Fortune" => 7,
            "Max Fortune" => 7
          },
          campaign_id: campaign.id
        })

      # Create fight event - the LATEST event is what gets shown
      %FightEvent{}
      |> FightEvent.changeset(%{
        event_type: "character_added",
        description: "Character Brick Manly added",
        fight_id: fight.id
      })
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        character_id: brick.id,
        shot: 12
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      # Note: trailing space after "**Brick Manly** " matches Rails output
      expected =
        "# Museum Battle\n" <>
          "The Christening of the Immortal Woman, featuring Huan Ken, King of the Thunder Pagoda\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 12\n" <>
          "- **Brick Manly** \n" <>
          " Guns 15 Defense 14 Fortune 7/7 Toughness 7 Speed 7\n" <>
          "\n" <>
          "Character Brick Manly added\n"

      assert result == expected
    end
  end

  describe "with two characters" do
    test "shows characters with impairments", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          description:
            "The Christening of the [@Immortal Woman](/sites/72f84df7-6dfc-42f3-8d55-dba8e40d3190), featuring [@Huan Ken](/characters/2bb9d3d6-3255-4d81-b7c4-64b17b95bbc5), King of the [@Thunder Pagoda](/factions/d9bc6c2f-ebe1-4300-a836-dcb36e6454ab)",
          campaign_id: campaign.id,
          sequence: 1
        })

      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "Fortune" => 7,
            "Max Fortune" => 7
          },
          campaign_id: campaign.id
        })

      {:ok, serena} =
        Characters.create_character(%{
          name: "Serena",
          action_values: %{
            "Type" => "PC",
            "MainAttack" => "Sorcery",
            "FortuneType" => "Magic",
            "Sorcery" => 14,
            "Defense" => 13,
            "Toughness" => 7,
            "Speed" => 6,
            "Fortune" => 5,
            "Max Fortune" => 7
          },
          impairments: 1,
          campaign_id: campaign.id
        })

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        character_id: brick.id,
        shot: 12
      })
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        character_id: serena.id,
        shot: 14
      })
      |> Repo.insert!()

      %FightEvent{}
      |> FightEvent.changeset(%{
        event_type: "attack",
        description: "Brick Manly attacked Serena doing 12 Wounds and spent 3 Shots",
        fight_id: fight.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      expected =
        "# Museum Battle\n" <>
          "The Christening of the Immortal Woman, featuring Huan Ken, King of the Thunder Pagoda\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 14\n" <>
          "- **Serena** \n" <>
          " (1 Impairment)\n" <>
          " Sorcery 13* Defense 12* Magic 5/7 Toughness 7 Speed 6\n" <>
          "## Shot 12\n" <>
          "- **Brick Manly** \n" <>
          " Guns 15 Defense 14 Fortune 7/7 Toughness 7 Speed 7\n" <>
          "\n" <>
          "Brick Manly attacked Serena doing 12 Wounds and spent 3 Shots\n"

      assert result == expected
    end
  end

  describe "with character effects" do
    test "shows character effects in diff block", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          campaign_id: campaign.id,
          sequence: 1
        })

      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "Fortune" => 7,
            "Max Fortune" => 7,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      {:ok, shot} =
        %Shot{}
        |> Shot.changeset(%{
          fight_id: fight.id,
          character_id: brick.id,
          shot: 12
        })
        |> Repo.insert()

      # Add character effects
      %CharacterEffect{}
      |> CharacterEffect.changeset(%{
        name: "Bonus",
        description: "Got lucky",
        severity: "info",
        action_value: "MainAttack",
        change: "+1",
        shot_id: shot.id,
        character_id: brick.id
      })
      |> Repo.insert!()

      %CharacterEffect{}
      |> CharacterEffect.changeset(%{
        name: "Blinded",
        description: "",
        severity: "error",
        action_value: "Defense",
        change: "-1",
        shot_id: shot.id,
        character_id: brick.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      expected =
        "# Museum Battle\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 12\n" <>
          "- **Brick Manly** \n" <>
          " Guns 15 Defense 14 Fortune 7/7 Toughness 7 Speed 7\n" <>
          "  ```diff\n" <>
          " Bonus: (Got lucky) Guns +1\n" <>
          " - Blinded: Defense -1\n" <>
          " ```\n"

      assert result == expected
    end
  end

  describe "with vehicles" do
    test "shows vehicle stats", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Chase Scene",
          campaign_id: campaign.id,
          sequence: 1
        })

      {:ok, pc_vehicle} =
        Vehicles.create_vehicle(%{
          name: "PC Vehicle",
          action_values: %{
            "Type" => "PC",
            "Acceleration" => 7,
            "Handling" => 10,
            "Squeal" => 12,
            "Frame" => 8,
            "Crunch" => 10,
            "Condition Points" => 14,
            "Chase Points" => 12,
            "Pursuer" => "false",
            "Position" => "far"
          },
          campaign_id: campaign.id
        })

      {:ok, boss_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Boss Vehicle",
          action_values: %{
            "Type" => "Boss",
            "Acceleration" => 7,
            "Handling" => 10,
            "Squeal" => 12,
            "Frame" => 8,
            "Crunch" => 10,
            "Condition Points" => 10,
            "Chase Points" => 24,
            "Pursuer" => "true",
            "Position" => "far"
          },
          campaign_id: campaign.id
        })

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        vehicle_id: pc_vehicle.id,
        shot: 8
      })
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        vehicle_id: boss_vehicle.id,
        shot: 10
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      expected =
        "# Chase Scene\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 10\n" <>
          "- **Boss Vehicle** \n" <>
          " Pursuer - far\n" <>
          "## Shot 8\n" <>
          "- **PC Vehicle** \n" <>
          " Evader - far\n" <>
          " 12 Chase 14 Condition Points\n" <>
          " Acceleration 7 Handling 10 Squeal 12 Frame 8\n"

      assert result == expected
    end
  end

  describe "with fight-level effects" do
    test "shows active effects in diff block", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          campaign_id: campaign.id,
          sequence: 1
        })

      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        character_id: brick.id,
        shot: 14
      })
      |> Repo.insert!()

      # Add fight-level effects
      %Effect{}
      |> Effect.changeset(%{
        name: "Shadow of the Sniper",
        description: "+1 Attack",
        severity: "success",
        start_sequence: 1,
        end_sequence: 2,
        start_shot: 14,
        end_shot: 14,
        fight_id: fight.id
      })
      |> Repo.insert!()

      %Effect{}
      |> Effect.changeset(%{
        name: "Some effect",
        description: "",
        severity: "error",
        start_sequence: 1,
        end_sequence: 2,
        start_shot: 16,
        end_shot: 16,
        fight_id: fight.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      expected =
        "# Museum Battle\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "```diff\n" <>
          "- Some effect (until sequence 2, shot 16)\n" <>
          "+ Shadow of the Sniper: +1 Attack (until sequence 2, shot 14)\n" <>
          "```\n" <>
          "## Shot 14\n" <>
          "- **Brick Manly** \n" <>
          " Guns 15 Defense 14 Toughness 7 Speed 7\n"

      assert result == expected
    end
  end

  describe "with character locations" do
    test "shows location after character name", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          campaign_id: campaign.id,
          sequence: 1
        })

      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      # Create location
      {:ok, control_room} = Fights.create_fight_location(fight.id, %{"name" => "Control Room"})

      %Shot{}
      |> Shot.changeset(%{
        fight_id: fight.id,
        character_id: brick.id,
        shot: 12,
        location_id: control_room.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      expected =
        "# Museum Battle\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 12\n" <>
          "- **Brick Manly** (Control Room) \n" <>
          " Guns 15 Defense 14 Toughness 7 Speed 7\n"

      assert result == expected
    end
  end

  describe "bad guys vs good guys" do
    test "bad guys only show name, good guys show full stats", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          campaign_id: campaign.id,
          sequence: 1
        })

      # PC - should show full stats
      {:ok, pc} =
        Characters.create_character(%{
          name: "Hero",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      # Ally - should show full stats
      {:ok, ally} =
        Characters.create_character(%{
          name: "Sidekick",
          action_values: %{
            "Type" => "Ally",
            "Guns" => 12,
            "Defense" => 12,
            "Toughness" => 6,
            "Speed" => 6,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      # Uber-Boss - should only show name
      {:ok, uber_boss} =
        Characters.create_character(%{
          name: "Thunder King",
          action_values: %{
            "Type" => "Uber-Boss",
            "Guns" => 18,
            "Defense" => 17,
            "Toughness" => 9,
            "Speed" => 8
          },
          campaign_id: campaign.id
        })

      # Mook - should only show name
      {:ok, mook} =
        Characters.create_character(%{
          name: "Ninja",
          action_values: %{
            "Type" => "Mook",
            "Guns" => 8,
            "Defense" => 13
          },
          campaign_id: campaign.id
        })

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: pc.id, shot: 12})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: ally.id, shot: 10})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: uber_boss.id, shot: 12})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: mook.id, shot: 5})
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      # Bad guys (Uber-Boss, Mook) only show name line
      # Good guys (PC, Ally) show full stats
      # Note: last line has no trailing space after trim_trailing()
      expected =
        "# Museum Battle\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 12\n" <>
          "- **Thunder King** \n" <>
          "- **Hero** \n" <>
          " Guns 15 Defense 14 Toughness 7 Speed 7\n" <>
          "## Shot 10\n" <>
          "- **Sidekick** \n" <>
          " Guns 12 Defense 12 Toughness 6 Speed 6\n" <>
          "## Shot 5\n" <>
          "- **Ninja**\n"

      assert result == expected
    end
  end

  describe "sort order" do
    test "sorts characters by type, then speed, then name", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          campaign_id: campaign.id,
          sequence: 1
        })

      # Uber-Boss (should be first)
      {:ok, uber_boss} =
        Characters.create_character(%{
          name: "Thunder King",
          action_values: %{"Type" => "Uber-Boss", "Speed" => 8},
          campaign_id: campaign.id
        })

      # PC (should be after Uber-Boss)
      {:ok, pc} =
        Characters.create_character(%{
          name: "Hero",
          action_values: %{"Type" => "PC", "Speed" => 7, "MainAttack" => "Guns"},
          campaign_id: campaign.id
        })

      # Mook (should be last)
      {:ok, mook} =
        Characters.create_character(%{
          name: "Ninja",
          action_values: %{"Type" => "Mook", "Speed" => 6},
          campaign_id: campaign.id
        })

      # All at the same shot
      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: uber_boss.id, shot: 10})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: pc.id, shot: 10})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: mook.id, shot: 10})
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      # Sort order: Uber-Boss > Boss > PC > Ally > Featured Foe > Mook
      # Note: last line has no trailing space after trim_trailing()
      expected =
        "# Museum Battle\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "## Shot 10\n" <>
          "- **Thunder King** \n" <>
          "- **Hero** \n" <>
          " Speed 7\n" <>
          "- **Ninja**\n"

      assert result == expected
    end
  end

  describe "comprehensive test with characters and vehicles" do
    test "matches Rails output exactly", %{campaign: campaign} do
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Museum Battle",
          description:
            "The Christening of the [@Immortal Woman](/sites/72f84df7-6dfc-42f3-8d55-dba8e40d3190), featuring [@Huan Ken](/characters/2bb9d3d6-3255-4d81-b7c4-64b17b95bbc5), King of the [@Thunder Pagoda](/factions/d9bc6c2f-ebe1-4300-a836-dcb36e6454ab)",
          campaign_id: campaign.id,
          sequence: 1
        })

      # Uber-Boss
      {:ok, thunder_king} =
        Characters.create_character(%{
          name: "Thunder King",
          action_values: %{
            "Type" => "Uber-Boss",
            "Guns" => 18,
            "Defense" => 17,
            "Toughness" => 9,
            "Speed" => 8
          },
          campaign_id: campaign.id
        })

      # Boss
      {:ok, shing} =
        Characters.create_character(%{
          name: "Ugly Shing",
          action_values: %{
            "Type" => "Boss",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7
          },
          campaign_id: campaign.id
        })

      # Featured Foe
      {:ok, hitman} =
        Characters.create_character(%{
          name: "Hitman",
          action_values: %{
            "Type" => "Featured Foe",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7
          },
          campaign_id: campaign.id
        })

      # Ally
      {:ok, jawbuster} =
        Characters.create_character(%{
          name: "Jawbuster",
          action_values: %{
            "Type" => "Ally",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "Wounds" => 12,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      # Mook
      {:ok, mook} =
        Characters.create_character(%{
          name: "Ninja",
          action_values: %{
            "Type" => "Mook",
            "Guns" => 8,
            "Defense" => 13,
            "Toughness" => 7,
            "Speed" => 6
          },
          campaign_id: campaign.id
        })

      # PC
      {:ok, brick} =
        Characters.create_character(%{
          name: "Brick Manly",
          action_values: %{
            "Type" => "PC",
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Speed" => 7,
            "Fortune" => 7,
            "Max Fortune" => 7,
            "MainAttack" => "Guns"
          },
          campaign_id: campaign.id
        })

      # PC with impairments
      {:ok, serena} =
        Characters.create_character(%{
          name: "Serena",
          action_values: %{
            "Type" => "PC",
            "MainAttack" => "Sorcery",
            "FortuneType" => "Magic",
            "Sorcery" => 14,
            "Defense" => 13,
            "Toughness" => 7,
            "Speed" => 6,
            "Fortune" => 5,
            "Max Fortune" => 7,
            "Wounds" => 39
          },
          impairments: 2,
          campaign_id: campaign.id
        })

      # Boss Vehicle
      {:ok, boss_vehicle} =
        Vehicles.create_vehicle(%{
          name: "Boss Vehicle",
          action_values: %{
            "Type" => "Boss",
            "Acceleration" => 7,
            "Handling" => 10,
            "Squeal" => 12,
            "Frame" => 8,
            "Crunch" => 10,
            "Condition Points" => 10,
            "Chase Points" => 24,
            "Pursuer" => "true",
            "Position" => "far"
          },
          campaign_id: campaign.id
        })

      # PC Vehicle
      {:ok, pc_vehicle} =
        Vehicles.create_vehicle(%{
          name: "PC Vehicle",
          action_values: %{
            "Type" => "PC",
            "Acceleration" => 7,
            "Handling" => 10,
            "Squeal" => 12,
            "Frame" => 8,
            "Crunch" => 10,
            "Condition Points" => 14,
            "Chase Points" => 12,
            "Pursuer" => "false",
            "Position" => "far"
          },
          campaign_id: campaign.id
        })

      # PC Mini
      {:ok, mini} =
        Vehicles.create_vehicle(%{
          name: "PC Mini",
          impairments: 1,
          action_values: %{
            "Type" => "PC",
            "Acceleration" => 7,
            "Handling" => 10,
            "Squeal" => 12,
            "Frame" => 8,
            "Crunch" => 10,
            "Condition Points" => 26,
            "Chase Points" => 19,
            "Pursuer" => "false",
            "Position" => "near"
          },
          campaign_id: campaign.id
        })

      # Create locations
      {:ok, control_room} = Fights.create_fight_location(fight.id, %{"name" => "Control Room"})
      {:ok, highway} = Fights.create_fight_location(fight.id, %{"name" => "Highway"})

      # Create shots
      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: mook.id, shot: nil})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: jawbuster.id, shot: 10})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: hitman.id, shot: 9})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: shing.id, shot: 10})
      |> Repo.insert!()

      {:ok, brick_shot} =
        %Shot{}
        |> Shot.changeset(%{
          fight_id: fight.id,
          character_id: brick.id,
          shot: 12,
          location_id: control_room.id
        })
        |> Repo.insert()

      {:ok, serena_shot} =
        %Shot{}
        |> Shot.changeset(%{fight_id: fight.id, character_id: serena.id, shot: 14})
        |> Repo.insert()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, character_id: thunder_king.id, shot: 12})
      |> Repo.insert!()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, vehicle_id: boss_vehicle.id, shot: 10})
      |> Repo.insert!()

      {:ok, pc_vehicle_shot} =
        %Shot{}
        |> Shot.changeset(%{
          fight_id: fight.id,
          vehicle_id: pc_vehicle.id,
          shot: 8,
          location_id: highway.id
        })
        |> Repo.insert()

      %Shot{}
      |> Shot.changeset(%{fight_id: fight.id, vehicle_id: mini.id, shot: 8})
      |> Repo.insert!()

      # Character effects
      %CharacterEffect{}
      |> CharacterEffect.changeset(%{
        name: "Bonus",
        description: "Got lucky",
        severity: "info",
        action_value: "MainAttack",
        change: "+1",
        shot_id: brick_shot.id,
        character_id: brick.id
      })
      |> Repo.insert!()

      %CharacterEffect{}
      |> CharacterEffect.changeset(%{
        name: "Blinded",
        description: "",
        severity: "error",
        action_value: "Defense",
        change: "-1",
        shot_id: brick_shot.id,
        character_id: brick.id
      })
      |> Repo.insert!()

      %CharacterEffect{}
      |> CharacterEffect.changeset(%{
        name: "Feeling weird",
        shot_id: serena_shot.id,
        character_id: serena.id
      })
      |> Repo.insert!()

      %CharacterEffect{}
      |> CharacterEffect.changeset(%{
        name: "Blinded",
        description: "",
        severity: "error",
        action_value: "Handling",
        change: "-1",
        shot_id: pc_vehicle_shot.id,
        vehicle_id: pc_vehicle.id
      })
      |> Repo.insert!()

      # Fight-level effects
      %Effect{}
      |> Effect.changeset(%{
        name: "Shadow of the Sniper",
        description: "+1 Attack",
        severity: "success",
        start_sequence: 1,
        end_sequence: 2,
        start_shot: 14,
        end_shot: 14,
        fight_id: fight.id
      })
      |> Repo.insert!()

      %Effect{}
      |> Effect.changeset(%{
        name: "Some effect",
        description: "",
        severity: "error",
        start_sequence: 1,
        end_sequence: 2,
        start_shot: 16,
        end_shot: 16,
        fight_id: fight.id
      })
      |> Repo.insert!()

      %Effect{}
      |> Effect.changeset(%{
        name: "Some other effect",
        description: "",
        severity: "success",
        start_sequence: 1,
        end_sequence: 2,
        start_shot: 9,
        end_shot: 9,
        fight_id: fight.id
      })
      |> Repo.insert!()

      # Fight event
      %FightEvent{}
      |> FightEvent.changeset(%{
        event_type: "attack",
        description: "Brick Manly attacked Serena doing 12 Wounds and spent 3 Shots",
        fight_id: fight.id
      })
      |> Repo.insert!()

      result = FightPoster.shots(fight.id)

      # Rails expected output - matches shot-server/spec/services/fight_poster_spec.rb
      expected =
        "# Museum Battle\n" <>
          "The Christening of the Immortal Woman, featuring Huan Ken, King of the Thunder Pagoda\n" <>
          "\n" <>
          "## Sequence 1\n" <>
          "```diff\n" <>
          "- Some effect (until sequence 2, shot 16)\n" <>
          "+ Shadow of the Sniper: +1 Attack (until sequence 2, shot 14)\n" <>
          "```\n" <>
          "## Shot 14\n" <>
          "- **Serena** \n" <>
          " 39 Wounds (2 Impairments)\n" <>
          " Sorcery 12* Defense 11* Magic 5/7 Toughness 7 Speed 6\n" <>
          "  ```diff\n" <>
          " Feeling weird\n" <>
          " ```\n" <>
          "## Shot 12\n" <>
          "- **Thunder King** \n" <>
          "- **Brick Manly** (Control Room) \n" <>
          " Guns 15 Defense 14 Fortune 7/7 Toughness 7 Speed 7\n" <>
          "  ```diff\n" <>
          " Bonus: (Got lucky) Guns +1\n" <>
          " - Blinded: Defense -1\n" <>
          " ```\n" <>
          "## Shot 10\n" <>
          "- **Ugly Shing** \n" <>
          "- **Jawbuster** \n" <>
          " 12 Wounds\n" <>
          " Guns 15 Defense 14 Toughness 7 Speed 7\n" <>
          "- **Boss Vehicle** \n" <>
          " Pursuer - far\n" <>
          "## Shot 9\n" <>
          "- **Hitman** \n" <>
          "## Shot 8\n" <>
          "- **PC Vehicle** (Highway) \n" <>
          " Evader - far\n" <>
          " 12 Chase 14 Condition Points\n" <>
          " Acceleration 7 Handling 10 Squeal 12 Frame 8\n" <>
          "  ```diff\n" <>
          " - Blinded: Handling -1\n" <>
          " ```\n" <>
          "- **PC Mini** \n" <>
          " Evader - near\n" <>
          " 19 Chase 26 Condition Points (1 Impairment)\n" <>
          " Acceleration 7 Handling 10 Squeal 12 Frame 8\n" <>
          "\n" <>
          "Brick Manly attacked Serena doing 12 Wounds and spent 3 Shots\n"

      assert result == expected
    end
  end
end
