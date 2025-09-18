defmodule ShotElixir.Characters do
  @moduledoc """
  The Characters context for managing Feng Shui 2 characters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character

  @character_types ["PC", "Ally", "Mook", "Featured Foe", "Boss", "Uber-Boss"]

  def list_characters(campaign_id) do
    query = from c in Character,
      where: c.campaign_id == ^campaign_id and c.active == true

    Repo.all(query)
  end

  def get_character!(id), do: Repo.get!(Character, id)
  def get_character(id), do: Repo.get(Character, id)

  def create_character(attrs \\ %{}) do
    %Character{}
    |> Character.changeset(attrs)
    |> Repo.insert()
  end

  def update_character(%Character{} = character, attrs) do
    character
    |> Character.changeset(attrs)
    |> Repo.update()
  end

  def delete_character(%Character{} = character) do
    character
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def duplicate_character(%Character{} = character, new_name) do
    attrs = Map.from_struct(character)
    |> Map.delete(:id)
    |> Map.delete(:__meta__)
    |> Map.put(:name, new_name)

    create_character(attrs)
  end
end