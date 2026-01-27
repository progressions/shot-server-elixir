defmodule ShotElixir.Effects do
  @moduledoc """
  The Effects context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Effects.CharacterEffect
  alias ShotElixir.Effects.Effect
  alias ShotElixir.Fights
  alias ShotElixir.Fights.Fight

  @doc """
  Gets a single character_effect.
  Returns nil if the CharacterEffect does not exist.
  """
  def get_character_effect(id), do: Repo.get(CharacterEffect, id)

  @doc """
  Gets a single character_effect belonging to a specific fight.
  Returns nil if not found.
  """
  def get_character_effect_for_fight(fight_id, effect_id) do
    from(ce in CharacterEffect,
      join: s in assoc(ce, :shot),
      where: ce.id == ^effect_id and s.fight_id == ^fight_id
    )
    |> Repo.one()
  end

  @doc """
  Creates a character_effect.
  """
  def create_character_effect(attrs \\ %{}) do
    %CharacterEffect{}
    |> CharacterEffect.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a character_effect.
  """
  def update_character_effect(%CharacterEffect{} = character_effect, attrs) do
    character_effect
    |> CharacterEffect.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a character_effect.
  """
  def delete_character_effect(%CharacterEffect{} = character_effect) do
    Repo.delete(character_effect)
  end

  @doc """
  Returns a list of all character effects for a given fight.
  """
  def list_character_effects_for_fight(fight_id) do
    from(ce in CharacterEffect,
      join: s in assoc(ce, :shot),
      where: s.fight_id == ^fight_id,
      preload: [:character, :vehicle, :shot]
    )
    |> Repo.all()
  end

  @doc """
  Finds and removes expired character effects for a fight.
  Creates a FightEvent for each expired effect.
  Returns {:ok, expired_effects} with the list of expired effect names.

  Expiry logic (shots count DOWN from 18 to 0):
  - If end_sequence is set and current_sequence > end_sequence: expired
  - If end_sequence matches and current shot < end_shot: expired
  - If only end_shot is set (no end_sequence): expires when current shot < end_shot
  """
  def expire_effects_for_fight(%Fight{} = fight) do
    # Find all character effects for this fight with expiry set
    expired_effects =
      from(ce in CharacterEffect,
        join: s in assoc(ce, :shot),
        where: s.fight_id == ^fight.id,
        where: not is_nil(ce.end_shot),
        preload: [:character, :vehicle, :shot]
      )
      |> Repo.all()
      |> Enum.filter(fn effect ->
        is_expired?(effect, fight)
      end)

    # Process each expired effect
    Enum.each(expired_effects, fn effect ->
      # Get the character or vehicle name
      entity_name = get_entity_name(effect)

      # Create FightEvent for the expiry
      description =
        if effect.name do
          "Effect '#{effect.name}' expired on #{entity_name}"
        else
          "Effect expired on #{entity_name}"
        end

      Fights.create_fight_event(
        %{
          fight_id: fight.id,
          event_type: "effect_expired",
          description: description,
          details: %{
            "effect_name" => effect.name,
            "effect_id" => effect.id,
            "character_id" => effect.character_id,
            "vehicle_id" => effect.vehicle_id,
            "entity_name" => entity_name,
            "end_sequence" => effect.end_sequence,
            "end_shot" => effect.end_shot
          }
        },
        broadcast: false
      )

      # Delete the effect
      Repo.delete(effect)
    end)

    {:ok, expired_effects}
  end

  defp is_expired?(%CharacterEffect{} = effect, %Fight{} = fight) do
    current_shot = fight.sequence

    # If end_sequence is set, we'd need to track sequence number
    # For now, we only check end_shot against current shot
    # Shots count DOWN, so effect expires when current_shot < end_shot
    case {effect.end_sequence, effect.end_shot} do
      {nil, nil} ->
        # No expiry set
        false

      {nil, end_shot} ->
        # Only end_shot set - expires when current shot passes it
        current_shot < end_shot

      {_end_sequence, end_shot} ->
        # Both set - for now, just check end_shot
        # TODO: Add sequence_number tracking to Fight for full support
        current_shot < end_shot
    end
  end

  defp get_entity_name(%CharacterEffect{} = effect) do
    cond do
      effect.character && effect.character.name -> effect.character.name
      effect.vehicle && effect.vehicle.name -> effect.vehicle.name
      true -> "unknown"
    end
  end

  # Fight-level Effects (Effect schema)

  @doc """
  Gets a single fight effect.
  Returns nil if the Effect does not exist.
  """
  def get_effect(id), do: Repo.get(Effect, id)

  @doc """
  Gets a single fight effect belonging to a specific fight.
  Returns nil if not found.
  """
  def get_effect_for_fight(fight_id, effect_id) do
    from(e in Effect,
      where: e.id == ^effect_id and e.fight_id == ^fight_id
    )
    |> Repo.one()
  end

  @doc """
  Creates a fight effect.
  """
  def create_effect(attrs \\ %{}) do
    %Effect{}
    |> Effect.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a fight effect.
  """
  def update_effect(%Effect{} = effect, attrs) do
    effect
    |> Effect.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a fight effect.
  """
  def delete_effect(%Effect{} = effect) do
    Repo.delete(effect)
  end

  @doc """
  Returns a list of all fight effects for a given fight.
  """
  def list_effects_for_fight(fight_id) do
    from(e in Effect,
      where: e.fight_id == ^fight_id,
      order_by: [asc: e.created_at]
    )
    |> Repo.all()
  end
end
