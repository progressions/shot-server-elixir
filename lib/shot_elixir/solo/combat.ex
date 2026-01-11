defmodule ShotElixir.Solo.Combat do
  @moduledoc """
  Shared combat utilities for solo play.

  Provides common functions for extracting character stats and calculating combat results.
  Used by both SoloController (player actions) and SimpleBehavior (NPC actions).
  """

  @doc """
  Convert string or integer values to integer.
  action_values is stored as JSONB, so values could be strings or integers.
  """
  def to_integer(value) when is_integer(value), do: value

  def to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> 0
    end
  end

  def to_integer(_), do: 0

  @doc """
  Convert value to integer with a custom default.
  """
  def to_integer(value, _default) when is_integer(value), do: value

  def to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> default
    end
  end

  def to_integer(_, default), do: default

  @doc """
  Get a character's main attack value from action_values.
  Uses MainAttack to determine which skill to use (defaults to Guns).
  """
  def get_attack_value(character) do
    av = character.action_values || %{}
    main_attack = Map.get(av, "MainAttack", "Guns")
    av_value = Map.get(av, main_attack, 0)
    to_integer(av_value)
  end

  @doc """
  Get a character's defense value.
  Checks dedicated defense field first, then falls back to action_values.
  """
  def get_defense(character) do
    raw_defense =
      case character.defense do
        nil -> Map.get(character.action_values || %{}, "Defense", 0)
        value -> value
      end

    to_integer(raw_defense)
  end

  @doc """
  Get a character's toughness value from action_values.
  """
  def get_toughness(character) do
    raw_toughness = Map.get(character.action_values || %{}, "Toughness", 0)
    to_integer(raw_toughness)
  end

  @doc """
  Get a character's damage value from action_values.
  Defaults to 7 (standard weapon damage in Feng Shui 2).
  """
  def get_damage(character) do
    raw_damage = Map.get(character.action_values || %{}, "Damage", 7)
    to_integer(raw_damage, 7)
  end

  @doc """
  Get a character's speed value from action_values.
  """
  def get_speed(entity) do
    av = entity.action_values || %{}
    Map.get(av, "Speed", 0) |> to_integer()
  end

  @doc """
  Calculate combat outcome.
  Returns {outcome, hit?} where outcome is attack_roll - defense.
  """
  def calculate_outcome(attack_value, swerve_total, defense) do
    action_result = attack_value + swerve_total
    outcome = action_result - defense
    {outcome, outcome > 0, action_result}
  end

  @doc """
  Calculate damage dealt.
  Returns {actual_damage, smackdown} where smackdown can be negative.
  """
  def calculate_damage(base_damage, outcome, toughness) when outcome > 0 do
    smackdown = base_damage + outcome - toughness
    actual_damage = max(0, smackdown)
    {actual_damage, smackdown}
  end

  def calculate_damage(_base_damage, _outcome, _toughness), do: {0, 0}

  @doc """
  Get the shot cost for a given action type.
  """
  def get_shot_cost(:attack), do: 3
  def get_shot_cost(:defend), do: 1
  def get_shot_cost(:stunt), do: 3
  def get_shot_cost("attack"), do: 3
  def get_shot_cost("defend"), do: 1
  def get_shot_cost("stunt"), do: 3
  def get_shot_cost(_), do: 3
end
