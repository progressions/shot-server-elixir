defmodule ShotElixir.Effects do
  @moduledoc """
  The Effects context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Effects.CharacterEffect

  def create_character_effect(attrs \\ %{}) do
    %CharacterEffect{}
    |> CharacterEffect.changeset(attrs)
    |> Repo.insert()
  end
end
