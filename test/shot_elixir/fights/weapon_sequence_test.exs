defmodule ShotElixir.Fights.WeaponSequenceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.{Fights, Schticks, Weapons, Characters, Campaigns}

  setup do
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "loop@test.com",
        password: "password123",
        first_name: "Loop",
        last_name: " Tester",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        user_id: user.id
      })

    {:ok, weapon1} =
      Weapons.create_weapon(%{
        name: "Revolver",
        damage: 9,
        concealment: 2,
        reload_value: 6,
        campaign_id: campaign.id
      })

    {:ok, weapon2} =
      Weapons.create_weapon(%{
        name: "Desert Eagle",
        damage: 11,
        concealment: 3,
        reload_value: 3,
        campaign_id: campaign.id
      })

    {:ok, schtick} =
      Schticks.create_schtick(%{
        name: "Bag Full of Guns",
        campaign_id: campaign.id,
        metadata: %{"weapon_sequence" => [weapon1.id, weapon2.id]}
      })

    {:ok, fight} =
      Fights.create_fight(%{
        name: "Test Fight",
        campaign_id: campaign.id,
        sequence: 18
      })

    {:ok, character} =
      Characters.create_character(%{
        name: "Shooter",
        campaign_id: campaign.id,
        schtick_ids: [schtick.id]
      })

    {:ok, shot} =
      Fights.create_shot(%{
        fight_id: fight.id,
        character_id: character.id,
        shot: 10
      })

    %{
      fight: Fights.get_fight_with_shots(fight.id),
      shot: shot,
      schtick: schtick,
      weapon1: weapon1,
      weapon2: weapon2
    }
  end

  test "initializes and advances through weapon sequence", %{
    shot: shot,
    schtick: schtick,
    weapon1: weapon1,
    weapon2: weapon2
  } do
    {:ok, result} =
      Fights.advance_weapon_sequence(shot.id, schtick.id, initialize_only: true)

    assert result.current_index == 0
    assert result.weapon.id == weapon1.id

    {:ok, result} = Fights.advance_weapon_sequence(shot.id, schtick.id)
    assert result.current_index == 1
    assert result.weapon.id == weapon2.id

    # End of list without loop -> stays on last
    {:ok, result} = Fights.advance_weapon_sequence(shot.id, schtick.id)
    assert result.current_index == 1
  end

  test "loops when loop flag is true", %{shot: shot, schtick: schtick, weapon1: weapon1} do
    {:ok, schtick} =
      Schticks.update_schtick(schtick, %{
        metadata: Map.put(schtick.metadata, "loop", true)
      })

    {:ok, _} = Fights.advance_weapon_sequence(shot.id, schtick.id, initialize_only: true)
    {:ok, _} = Fights.advance_weapon_sequence(shot.id, schtick.id)
    {:ok, result} = Fights.advance_weapon_sequence(shot.id, schtick.id)

    assert result.current_index == 0
    assert result.weapon.id == weapon1.id
  end
end
