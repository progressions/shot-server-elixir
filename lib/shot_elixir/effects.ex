defmodule ShotElixir.Effects do
  @moduledoc """
  The Effects context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Effects.CharacterEffect

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
end
