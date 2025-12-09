defmodule ShotElixir.Services.CombatActionServiceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Services.CombatActionService
  alias ShotElixir.Characters
  alias ShotElixir.Factory

  describe "apply_combat_action/2 with status updates" do
    setup do
      user = Factory.insert(:user, %{gamemaster: true})
      campaign = Factory.insert(:campaign, %{user: user})
      fight = Factory.insert(:fight, %{campaign: campaign})

      {:ok, user: user, campaign: campaign, fight: fight}
    end

    test "adds status to character via add_status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "add_status" => ["cheesing_it"]
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Reload character and verify status was added
      updated_character = Characters.get_character(character.id)
      assert "cheesing_it" in updated_character.status
    end

    test "removes status from character via remove_status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          status: ["cheesing_it"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "remove_status" => ["cheesing_it"]
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Reload character and verify status was removed
      updated_character = Characters.get_character(character.id)
      refute "cheesing_it" in updated_character.status
    end

    test "adds and removes status in same update", %{campaign: campaign, fight: fight, user: user} do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          status: ["cheesing_it"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "remove_status" => ["cheesing_it"],
          "add_status" => ["cheesed_it"]
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Reload character and verify status changes
      updated_character = Characters.get_character(character.id)
      refute "cheesing_it" in updated_character.status
      assert "cheesed_it" in updated_character.status
    end

    test "handles escape attempt - adds cheesing_it status and updates shot", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character, shot: 10})

      # Simulate escape attempt: spend 3 shots and add cheesing_it status
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "shot" => 7,
          "add_status" => ["cheesing_it"],
          "event" => %{
            "type" => "escape_attempt",
            "description" => "#{character.name} is attempting to cheese it!",
            "details" => %{
              "character_id" => character.id,
              "shot_cost" => 3,
              "old_shot" => 10,
              "new_shot" => 7
            }
          }
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Reload and verify
      updated_character = Characters.get_character(character.id)
      assert "cheesing_it" in updated_character.status
    end

    test "handles speed check prevention - removes cheesing_it from escapee", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      preventer =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          name: "Preventer",
          status: []
        })

      escapee =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          name: "Escapee",
          status: ["cheesing_it"]
        })

      preventer_shot = Factory.insert(:shot, %{fight: fight, character: preventer, shot: 8})
      escapee_shot = Factory.insert(:shot, %{fight: fight, character: escapee, shot: 5})

      # Simulate successful prevention: preventer spends shots, escapee loses cheesing_it
      updates = [
        %{
          "shot_id" => preventer_shot.id,
          "character_id" => preventer.id,
          "shot" => 5,
          "event" => %{
            "type" => "speed_check_attempt",
            "description" => "Preventer spends 3 shots on Speed Check"
          }
        },
        %{
          "shot_id" => escapee_shot.id,
          "character_id" => escapee.id,
          "remove_status" => ["cheesing_it"],
          "event" => %{
            "type" => "escape_prevented",
            "description" => "Preventer prevents Escapee from escaping!"
          }
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Verify escapee no longer has cheesing_it status
      updated_escapee = Characters.get_character(escapee.id)
      refute "cheesing_it" in updated_escapee.status
    end

    test "handles failed speed check - escapee gets cheesed_it status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      preventer =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          name: "Preventer",
          status: []
        })

      escapee =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          name: "Escapee",
          status: ["cheesing_it"]
        })

      preventer_shot = Factory.insert(:shot, %{fight: fight, character: preventer, shot: 8})
      escapee_shot = Factory.insert(:shot, %{fight: fight, character: escapee, shot: 5})

      # Simulate failed prevention: preventer spends shots, escapee changes to cheesed_it
      updates = [
        %{
          "shot_id" => preventer_shot.id,
          "character_id" => preventer.id,
          "shot" => 5,
          "event" => %{
            "type" => "speed_check_attempt",
            "description" => "Preventer spends 3 shots on Speed Check"
          }
        },
        %{
          "shot_id" => escapee_shot.id,
          "character_id" => escapee.id,
          "remove_status" => ["cheesing_it"],
          "add_status" => ["cheesed_it"],
          "event" => %{
            "type" => "escape_succeeded",
            "description" => "Escapee successfully escapes!"
          }
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Verify escapee now has cheesed_it status (not cheesing_it)
      updated_escapee = Characters.get_character(escapee.id)
      refute "cheesing_it" in updated_escapee.status
      assert "cheesed_it" in updated_escapee.status
    end

    test "does not duplicate existing status", %{campaign: campaign, fight: fight, user: user} do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          status: ["cheesing_it"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "add_status" => ["cheesing_it"]
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Verify status is not duplicated
      updated_character = Characters.get_character(character.id)
      cheesing_count = Enum.count(updated_character.status, &(&1 == "cheesing_it"))
      assert cheesing_count == 1
    end

    test "preserves existing statuses when adding new ones", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          status: ["existing_status"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "add_status" => ["cheesing_it"]
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      # Verify both statuses exist
      updated_character = Characters.get_character(character.id)
      assert "existing_status" in updated_character.status
      assert "cheesing_it" in updated_character.status
    end

    test "skips updates without shot_id", %{fight: fight} do
      updates = [
        %{
          "character_id" => Ecto.UUID.generate(),
          "add_status" => ["cheesing_it"]
        }
      ]

      # Should succeed but skip the update
      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)
    end
  end

  describe "apply_combat_action/2 with up_check threshold" do
    setup do
      user = Factory.insert(:user, %{gamemaster: true})
      campaign = Factory.insert(:campaign, %{user: user})
      fight = Factory.insert(:fight, %{campaign: campaign})

      {:ok, user: user, campaign: campaign, fight: fight}
    end

    test "PC crossing 35 wound threshold adds up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 30},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      # Apply 10 wounds to cross the 35 threshold
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 10
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      assert "up_check_required" in updated_character.status
      assert updated_character.action_values["Wounds"] == 40
    end

    test "PC at exactly 35 wounds gets up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 30},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      # Apply 5 wounds to reach exactly 35
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 5
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      assert "up_check_required" in updated_character.status
    end

    test "PC below 35 wounds does not get up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 20},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      # Apply 10 wounds, total 30 - still below threshold
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 10
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      refute "up_check_required" in updated_character.status
    end

    test "Boss crossing 50 wound threshold adds up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "Boss"},
          status: []
        })

      # Boss wounds go to shot.count
      shot = Factory.insert(:shot, %{fight: fight, character: character, count: 45})

      # Apply 10 wounds to cross the 50 threshold
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 10
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      assert "up_check_required" in updated_character.status
    end

    test "Uber-Boss crossing 50 wound threshold adds up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "Uber-Boss"},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character, count: 48})

      # Apply 5 wounds to cross the 50 threshold
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 5
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      assert "up_check_required" in updated_character.status
    end

    test "Featured Foe does not get up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "Featured Foe"},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character, count: 20})

      # Apply lots of wounds - Featured Foes go straight to out_of_fight
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 50
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      refute "up_check_required" in updated_character.status
    end

    test "Ally does not get up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "Ally"},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character, count: 20})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 50
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      refute "up_check_required" in updated_character.status
    end

    test "Mook does not get up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "Mook"},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character, count: 5})

      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 10
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      refute "up_check_required" in updated_character.status
    end

    test "healing below threshold removes up_check_required status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 40},
          status: ["up_check_required"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      # Heal 10 wounds to go below 35 threshold
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => -10
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      refute "up_check_required" in updated_character.status
      assert updated_character.action_values["Wounds"] == 30
    end

    test "status not duplicated if already present", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 40},
          status: ["up_check_required"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      # Apply more wounds when already above threshold
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 5
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      up_check_count = Enum.count(updated_character.status, &(&1 == "up_check_required"))
      assert up_check_count == 1
    end

    test "status enforced if manually removed while above threshold", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      # Character above threshold but without the status (simulating manual removal)
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 40},
          status: []
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character})

      # Apply more wounds - should re-add the status
      updates = [
        %{
          "shot_id" => shot.id,
          "character_id" => character.id,
          "wounds" => 5
        }
      ]

      assert {:ok, _fight} = CombatActionService.apply_combat_action(fight, updates)

      updated_character = Characters.get_character(character.id)
      assert "up_check_required" in updated_character.status
    end
  end
end
