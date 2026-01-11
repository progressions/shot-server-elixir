defmodule ShotElixir.Solo.SimpleBehaviorTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Solo.SimpleBehavior

  describe "behavior_type/0" do
    test "returns :simple" do
      assert SimpleBehavior.behavior_type() == :simple
    end
  end

  describe "find_target/1" do
    test "returns nil for empty list" do
      assert SimpleBehavior.find_target([]) == nil
    end

    test "returns the PC with highest shot value" do
      pc1 = %{character: %{id: "1", name: "PC1"}, shot: 5}
      pc2 = %{character: %{id: "2", name: "PC2"}, shot: 10}
      pc3 = %{character: %{id: "3", name: "PC3"}, shot: 3}

      result = SimpleBehavior.find_target([pc1, pc2, pc3])
      assert result.character.name == "PC2"
    end

    test "handles nil shot values" do
      pc1 = %{character: %{id: "1", name: "PC1"}, shot: nil}
      pc2 = %{character: %{id: "2", name: "PC2"}, shot: 5}

      result = SimpleBehavior.find_target([pc1, pc2])
      assert result.character.name == "PC2"
    end

    test "filters out entries with nil character" do
      pc1 = %{character: nil, shot: 100}
      pc2 = %{character: %{id: "2", name: "PC2"}, shot: 5}

      result = SimpleBehavior.find_target([pc1, pc2])
      assert result.character.name == "PC2"
    end
  end

  describe "execute_attack/2" do
    test "returns successful attack result with hit when outcome is positive" do
      attacker = %{
        id: "attacker-1",
        name: "NPC Attacker",
        action_values: %{
          "MainAttack" => "Guns",
          "Guns" => 13,
          "Damage" => 10
        }
      }

      target_shot = %{
        character: %{
          id: "target-1",
          name: "PC Target",
          defense: 12,
          action_values: %{"Toughness" => 5}
        }
      }

      {:ok, result} = SimpleBehavior.execute_attack(attacker, target_shot)

      assert result.action_type == :attack
      assert result.target_id == "target-1"
      assert is_binary(result.narrative)
      assert is_map(result.dice_result)
      assert is_integer(result.damage)
      assert is_integer(result.outcome)
      assert is_boolean(result.hit)
    end

    test "returns miss when outcome is zero or negative" do
      attacker = %{
        id: "attacker-1",
        name: "Weak Attacker",
        action_values: %{
          "MainAttack" => "Guns",
          "Guns" => 5,
          "Damage" => 7
        }
      }

      target_shot = %{
        character: %{
          id: "target-1",
          name: "Strong Defender",
          defense: 20,
          action_values: %{"Toughness" => 10}
        }
      }

      # Run multiple times since dice are random
      results =
        for _ <- 1..20 do
          {:ok, result} = SimpleBehavior.execute_attack(attacker, target_shot)
          result
        end

      # With low attack (5) vs high defense (20), most should miss
      misses = Enum.count(results, fn r -> r.hit == false end)
      assert misses > 0
    end

    test "includes dice result details" do
      attacker = %{
        id: "attacker-1",
        name: "Attacker",
        action_values: %{
          "MainAttack" => "Martial Arts",
          "Martial Arts" => 14,
          "Damage" => 8
        }
      }

      target_shot = %{
        character: %{
          id: "target-1",
          name: "Target",
          defense: 13,
          action_values: %{"Toughness" => 6}
        }
      }

      {:ok, result} = SimpleBehavior.execute_attack(attacker, target_shot)

      assert result.dice_result.attack_value == 14
      assert result.dice_result.defense == 13
      assert is_map(result.dice_result.swerve)
      assert is_integer(result.dice_result.action_result)
    end

    test "uses default Guns for MainAttack when not specified" do
      attacker = %{
        id: "attacker-1",
        name: "Default Attacker",
        action_values: %{
          "Guns" => 12,
          "Damage" => 9
        }
      }

      target_shot = %{
        character: %{
          id: "target-1",
          name: "Target",
          defense: 10,
          action_values: %{}
        }
      }

      {:ok, result} = SimpleBehavior.execute_attack(attacker, target_shot)
      assert result.dice_result.attack_value == 12
    end

    test "falls back to action_values Defense when defense field is nil" do
      attacker = %{
        id: "attacker-1",
        name: "Attacker",
        action_values: %{"Guns" => 10, "Damage" => 7}
      }

      target_shot = %{
        character: %{
          id: "target-1",
          name: "Target",
          defense: nil,
          action_values: %{"Defense" => 14, "Toughness" => 5}
        }
      }

      {:ok, result} = SimpleBehavior.execute_attack(attacker, target_shot)
      assert result.dice_result.defense == 14
    end
  end

  describe "determine_action/1" do
    test "returns error when no valid targets" do
      context = %{
        pc_shots: [],
        acting_character: %{id: "npc-1", name: "NPC"}
      }

      assert SimpleBehavior.determine_action(context) == {:error, :no_valid_target}
    end

    test "attacks the PC with highest shot" do
      context = %{
        pc_shots: [
          %{character: %{id: "pc-1", name: "Low Shot", defense: 10, action_values: %{}}, shot: 3},
          %{
            character: %{id: "pc-2", name: "High Shot", defense: 12, action_values: %{}},
            shot: 15
          }
        ],
        acting_character: %{
          id: "npc-1",
          name: "Attacker",
          action_values: %{"Guns" => 13, "Damage" => 8}
        }
      }

      {:ok, result} = SimpleBehavior.determine_action(context)
      assert result.action_type == :attack
      assert result.target_id == "pc-2"
    end
  end
end
