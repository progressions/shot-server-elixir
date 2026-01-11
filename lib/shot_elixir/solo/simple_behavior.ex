defmodule ShotElixir.Solo.SimpleBehavior do
  @moduledoc """
  Simple NPC behavior for solo play.

  Strategy: Attack the PC with the highest current shot value.
  Uses standard Feng Shui 2 combat mechanics.
  No narrative generation - just mechanical results.
  """

  @behaviour ShotElixir.Solo.Behavior

  alias ShotElixir.Services.DiceRoller

  @impl true
  def behavior_type, do: :simple

  @impl true
  def determine_action(context) do
    case find_target(context.pc_shots) do
      nil ->
        {:error, :no_valid_target}

      target_shot ->
        execute_attack(context.acting_character, target_shot)
    end
  end

  @doc """
  Find the PC with the highest current shot value.
  """
  def find_target([]), do: nil

  def find_target(pc_shots) do
    pc_shots
    |> Enum.filter(fn shot -> shot.character != nil end)
    |> Enum.max_by(fn shot -> shot.current_shot || 0 end, fn -> nil end)
  end

  @doc """
  Execute an attack against a target.
  Returns {:ok, action_result} with dice and damage calculations.
  """
  def execute_attack(attacker, target_shot) do
    target = target_shot.character
    swerve = DiceRoller.swerve()

    # Get attacker's main attack value
    attack_value = get_attack_value(attacker)

    # Get target's defense
    defense = get_defense(target)

    # Calculate outcome
    action_result = attack_value + swerve.total
    outcome = action_result - defense

    # Calculate damage if hit
    {damage, smackdown} =
      if outcome > 0 do
        base_damage = get_damage(attacker)
        toughness = get_toughness(target)
        smackdown = base_damage + outcome - toughness
        actual_damage = max(0, smackdown)
        {actual_damage, smackdown}
      else
        {0, 0}
      end

    result = %{
      action_type: :attack,
      target_id: target.id,
      narrative: build_simple_narrative(attacker, target, outcome, damage),
      dice_result: %{
        swerve: swerve,
        attack_value: attack_value,
        action_result: action_result,
        defense: defense
      },
      damage: damage,
      outcome: outcome,
      smackdown: smackdown,
      hit: outcome > 0
    }

    {:ok, result}
  end

  defp get_attack_value(character) do
    av = character.action_values || %{}
    main_attack = Map.get(av, "MainAttack", "Guns")
    Map.get(av, main_attack, 0)
  end

  defp get_defense(character) do
    # Check dedicated defense field first, then action_values
    character.defense ||
      Map.get(character.action_values || %{}, "Defense", 0)
  end

  defp get_toughness(character) do
    Map.get(character.action_values || %{}, "Toughness", 0)
  end

  defp get_damage(character) do
    Map.get(character.action_values || %{}, "Damage", 7)
  end

  defp build_simple_narrative(attacker, target, outcome, damage) do
    if outcome > 0 do
      "#{attacker.name} attacks #{target.name} for #{damage} damage!"
    else
      "#{attacker.name} attacks #{target.name} but misses!"
    end
  end
end
