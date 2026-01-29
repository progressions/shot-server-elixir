defmodule ShotElixir.Services.UpCheckServiceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Services.UpCheckService
  alias ShotElixir.{Characters, Fights}
  alias ShotElixir.Factory

  describe "apply_up_check/2" do
    setup do
      user = Factory.insert(:user, %{gamemaster: true})
      campaign = Factory.insert(:campaign, %{user: user})
      fight = Factory.insert(:fight, %{campaign: campaign})

      {:ok, user: user, campaign: campaign, fight: fight}
    end

    test "successful up check clears up_check_required status but does NOT reduce wounds", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      # PC with 40 wounds requiring an up check
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 40},
          status: ["up_check_required"]
        })

      _shot = Factory.insert(:shot, %{fight: fight, character: character})

      params = %{
        "character_id" => character.id,
        "success" => true,
        "result" => 6
      }

      assert {:ok, _fight} = UpCheckService.apply_up_check(fight, params)

      # Reload character and verify
      updated_character = Characters.get_character(character.id)

      # Status should be cleared
      refute "up_check_required" in updated_character.status

      # CRITICAL: Wounds should NOT be reduced - they stay at 40
      assert updated_character.action_values["Wounds"] == 40
    end

    test "successful up check for Boss does NOT reduce wounds on shot.count", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      # Boss with wounds stored in shot.count
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "Boss"},
          status: ["up_check_required"]
        })

      shot = Factory.insert(:shot, %{fight: fight, character: character, count: 55})

      params = %{
        "character_id" => character.id,
        "success" => true,
        "result" => 8
      }

      assert {:ok, _fight} = UpCheckService.apply_up_check(fight, params)

      # Reload character and shot
      updated_character = Characters.get_character(character.id)
      updated_shot = Fights.get_shot(shot.id)

      # Status should be cleared
      refute "up_check_required" in updated_character.status

      # CRITICAL: Wounds (shot.count) should NOT be reduced - they stay at 55
      assert updated_shot.count == 55
    end

    test "failed up check marks character as out_of_fight", %{
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

      _shot = Factory.insert(:shot, %{fight: fight, character: character})

      params = %{
        "character_id" => character.id,
        "success" => false,
        "result" => 4
      }

      assert {:ok, _fight} = UpCheckService.apply_up_check(fight, params)

      updated_character = Characters.get_character(character.id)

      # up_check_required should be removed
      refute "up_check_required" in updated_character.status

      # Character should be out of the fight
      assert "out_of_fight" in updated_character.status
    end

    test "failed up check does not duplicate out_of_fight status", %{
      campaign: campaign,
      fight: fight,
      user: user
    } do
      character =
        Factory.insert(:character, %{
          campaign: campaign,
          user: user,
          action_values: %{"Type" => "PC", "Wounds" => 40},
          status: ["up_check_required", "out_of_fight"]
        })

      _shot = Factory.insert(:shot, %{fight: fight, character: character})

      params = %{
        "character_id" => character.id,
        "success" => false,
        "result" => 3
      }

      assert {:ok, _fight} = UpCheckService.apply_up_check(fight, params)

      updated_character = Characters.get_character(character.id)
      out_count = Enum.count(updated_character.status, &(&1 == "out_of_fight"))
      assert out_count == 1
    end
  end
end
