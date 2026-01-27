defmodule ShotElixir.EffectsTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Effects
  alias ShotElixir.Effects.CharacterEffect
  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Fights
  alias ShotElixir.Repo

  setup do
    # Create a user and a campaign
    {:ok, user} =
      ShotElixir.Accounts.create_user(%{
        email: "testeffects@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign for Effects",
        user_id: user.id
      })

    # Create a character
    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id
      })

    # Create a fight
    {:ok, fight} =
      Fights.create_fight(%{
        name: "Test Fight",
        campaign_id: campaign.id,
        sequence: 15
      })

    # Add the character to the fight (creates a shot)
    {:ok, shot} =
      Fights.create_shot(%{
        fight_id: fight.id,
        character_id: character.id,
        shot: 15
      })

    {:ok, user: user, campaign: campaign, character: character, fight: fight, shot: shot}
  end

  describe "expire_effects_for_fight/1" do
    test "expires effects when current shot passes end_shot", %{
      fight: fight,
      character: character,
      shot: shot
    } do
      # Create an effect that expires at shot 16 (fight is at shot 15, so this should be expired)
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Stunned",
          severity: "warning",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 16
        })

      # Verify the effect exists
      assert Effects.get_character_effect(effect.id)

      # Call expire_effects_for_fight
      {:ok, expired} = Effects.expire_effects_for_fight(fight)

      # The effect should have been expired
      assert length(expired) == 1
      assert hd(expired).id == effect.id

      # The effect should be deleted
      refute Effects.get_character_effect(effect.id)
    end

    test "does not expire effects when current shot has not passed end_shot", %{
      fight: fight,
      character: character,
      shot: shot
    } do
      # Create an effect that expires at shot 10 (fight is at shot 15, so not expired yet)
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Blessed",
          severity: "success",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 10
        })

      # Call expire_effects_for_fight
      {:ok, expired} = Effects.expire_effects_for_fight(fight)

      # No effects should be expired
      assert expired == []

      # The effect should still exist
      assert Effects.get_character_effect(effect.id)
    end

    test "does not expire effects with no expiry set", %{
      fight: fight,
      character: character,
      shot: shot
    } do
      # Create a permanent effect (no end_shot)
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Permanent Effect",
          severity: "info",
          character_id: character.id,
          shot_id: shot.id
        })

      # Call expire_effects_for_fight
      {:ok, expired} = Effects.expire_effects_for_fight(fight)

      # No effects should be expired
      assert expired == []

      # The effect should still exist
      assert Effects.get_character_effect(effect.id)
    end

    test "creates a FightEvent when an effect expires", %{
      fight: fight,
      character: character,
      shot: shot
    } do
      # Create an effect that will expire
      {:ok, _effect} =
        Effects.create_character_effect(%{
          name: "Stunned",
          severity: "error",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 16
        })

      # Get initial fight events count
      initial_events = Fights.list_fight_events(fight.id)
      initial_count = length(initial_events)

      # Expire effects
      {:ok, _expired} = Effects.expire_effects_for_fight(fight)

      # Check that a fight event was created
      events = Fights.list_fight_events(fight.id)
      assert length(events) == initial_count + 1

      event = List.last(events)
      assert event.event_type == "effect_expired"
      assert String.contains?(event.description, "Stunned")
      assert event.details["effect_name"] == "Stunned"
    end

    test "expires multiple effects at once", %{
      fight: fight,
      character: character,
      shot: shot
    } do
      # Create multiple effects that will expire
      {:ok, effect1} =
        Effects.create_character_effect(%{
          name: "Effect 1",
          severity: "warning",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 18
        })

      {:ok, effect2} =
        Effects.create_character_effect(%{
          name: "Effect 2",
          severity: "error",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 16
        })

      # Create one that won't expire
      {:ok, effect3} =
        Effects.create_character_effect(%{
          name: "Effect 3",
          severity: "info",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 10
        })

      # Expire effects
      {:ok, expired} = Effects.expire_effects_for_fight(fight)

      # Two effects should have expired
      assert length(expired) == 2
      expired_ids = Enum.map(expired, & &1.id)
      assert effect1.id in expired_ids
      assert effect2.id in expired_ids
      refute effect3.id in expired_ids

      # Only effect3 should remain
      assert Effects.get_character_effect(effect3.id)
      refute Effects.get_character_effect(effect1.id)
      refute Effects.get_character_effect(effect2.id)
    end

    test "effect expires exactly at the boundary shot", %{
      campaign: campaign,
      character: character
    } do
      # Create a fight at exactly shot 10
      {:ok, fight} =
        Fights.create_fight(%{
          name: "Boundary Test Fight",
          campaign_id: campaign.id,
          sequence: 10
        })

      {:ok, shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          character_id: character.id,
          shot: 10
        })

      # Effect expires at shot 10 - should NOT be expired yet (expires when shot PASSES it)
      {:ok, effect_at_boundary} =
        Effects.create_character_effect(%{
          name: "At Boundary",
          severity: "warning",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 10
        })

      {:ok, expired} = Effects.expire_effects_for_fight(fight)
      assert expired == []
      assert Effects.get_character_effect(effect_at_boundary.id)

      # Now create a fight at shot 9 (past the boundary)
      {:ok, fight2} =
        Fights.create_fight(%{
          name: "Past Boundary Fight",
          campaign_id: campaign.id,
          sequence: 9
        })

      {:ok, shot2} =
        Fights.create_shot(%{
          fight_id: fight2.id,
          character_id: character.id,
          shot: 9
        })

      {:ok, effect2} =
        Effects.create_character_effect(%{
          name: "Past Boundary",
          severity: "warning",
          character_id: character.id,
          shot_id: shot2.id,
          end_shot: 10
        })

      {:ok, expired2} = Effects.expire_effects_for_fight(fight2)
      assert length(expired2) == 1
      assert hd(expired2).id == effect2.id
    end
  end

  describe "create_character_effect/1 with expiry fields" do
    test "creates effect with end_sequence and end_shot", %{
      character: character,
      shot: shot
    } do
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Timed Effect",
          severity: "info",
          character_id: character.id,
          shot_id: shot.id,
          end_sequence: 2,
          end_shot: 5
        })

      assert effect.end_sequence == 2
      assert effect.end_shot == 5
    end

    test "creates effect with only end_shot (no sequence)", %{
      character: character,
      shot: shot
    } do
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Shot-only Expiry",
          severity: "warning",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 8
        })

      assert effect.end_sequence == nil
      assert effect.end_shot == 8
    end
  end

  describe "integration with advance_shot_counter" do
    test "advancing shot counter triggers effect expiry", %{
      fight: fight,
      character: character,
      shot: shot
    } do
      # Fight starts at shot 15
      # Create an effect that expires at shot 15 (will expire when we advance to 14)
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Will Expire",
          severity: "warning",
          character_id: character.id,
          shot_id: shot.id,
          end_shot: 15
        })

      # Verify effect exists
      assert Effects.get_character_effect(effect.id)

      # Advance the shot counter (15 -> 14)
      {:ok, updated_fight} = Fights.advance_shot_counter(fight)
      assert updated_fight.sequence == 14

      # The effect should have been expired
      refute Effects.get_character_effect(effect.id)

      # A fight event should have been created
      events = Fights.list_fight_events(fight.id)
      expiry_event = Enum.find(events, &(&1.event_type == "effect_expired"))
      assert expiry_event
      assert String.contains?(expiry_event.description, "Will Expire")
    end
  end

  describe "vehicle effects" do
    setup %{campaign: campaign, fight: fight} do
      # Create a vehicle with required action_values
      {:ok, vehicle} =
        ShotElixir.Vehicles.create_vehicle(%{
          name: "Test Vehicle",
          campaign_id: campaign.id,
          action_values: %{
            "Acceleration" => 5,
            "Handling" => 5,
            "Frame" => 5,
            "Crunch" => 5
          }
        })

      # Add the vehicle to the fight (creates a shot)
      {:ok, vehicle_shot} =
        Fights.create_shot(%{
          fight_id: fight.id,
          vehicle_id: vehicle.id,
          shot: 15
        })

      {:ok, vehicle: vehicle, vehicle_shot: vehicle_shot}
    end

    test "expires vehicle effects when current shot passes end_shot", %{
      fight: fight,
      vehicle: vehicle,
      vehicle_shot: vehicle_shot
    } do
      # Create a vehicle effect that expires at shot 16 (fight is at shot 15, so this should be expired)
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Vehicle Stunned",
          severity: "warning",
          vehicle_id: vehicle.id,
          shot_id: vehicle_shot.id,
          end_shot: 16
        })

      # Verify the effect exists
      assert Effects.get_character_effect(effect.id)

      # Call expire_effects_for_fight
      {:ok, expired} = Effects.expire_effects_for_fight(fight)

      # The effect should have been expired
      assert length(expired) == 1
      assert hd(expired).id == effect.id

      # The effect should be deleted
      refute Effects.get_character_effect(effect.id)
    end

    test "creates FightEvent with vehicle name when vehicle effect expires", %{
      fight: fight,
      vehicle: vehicle,
      vehicle_shot: vehicle_shot
    } do
      # Create a vehicle effect that will expire
      {:ok, _effect} =
        Effects.create_character_effect(%{
          name: "Engine Damage",
          severity: "error",
          vehicle_id: vehicle.id,
          shot_id: vehicle_shot.id,
          end_shot: 16
        })

      # Expire effects
      {:ok, _expired} = Effects.expire_effects_for_fight(fight)

      # Check that a fight event was created with vehicle name
      events = Fights.list_fight_events(fight.id)
      event = Enum.find(events, &(&1.event_type == "effect_expired"))
      assert event
      assert String.contains?(event.description, "Engine Damage")
      assert String.contains?(event.description, "Test Vehicle")
      assert event.details["vehicle_id"] == vehicle.id
    end

    test "does not expire vehicle effects when current shot has not passed end_shot", %{
      fight: fight,
      vehicle: vehicle,
      vehicle_shot: vehicle_shot
    } do
      # Create a vehicle effect that expires at shot 10 (fight is at shot 15, so not expired yet)
      {:ok, effect} =
        Effects.create_character_effect(%{
          name: "Speed Boost",
          severity: "success",
          vehicle_id: vehicle.id,
          shot_id: vehicle_shot.id,
          end_shot: 10
        })

      # Call expire_effects_for_fight
      {:ok, expired} = Effects.expire_effects_for_fight(fight)

      # No effects should be expired
      assert expired == []

      # The effect should still exist
      assert Effects.get_character_effect(effect.id)
    end
  end
end
