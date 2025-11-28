defmodule ShotElixir.Services.CombatActionServiceTest do
  use ShotElixir.DataCase

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
end
