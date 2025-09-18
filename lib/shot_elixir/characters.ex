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

  def list_campaign_characters(campaign_id, params \\ %{}) do
    query = from c in Character,
      where: c.campaign_id == ^campaign_id and c.active == true

    # Apply filters
    query = if params["search"] do
      from c in query, where: ilike(c.name, ^"%#{params["search"]}%")
    else
      query
    end

    query = if params["character_type"] do
      from c in query, where: fragment("?->>'Type' = ?", c.action_values, ^params["character_type"])
    else
      query
    end

    query = if params["faction_id"] do
      from c in query, where: c.faction_id == ^params["faction_id"]
    else
      query
    end

    Repo.all(query |> order_by([c], asc: c.name))
  end

  def search_characters(campaign_id, search_term) do
    query = from c in Character,
      where: c.campaign_id == ^campaign_id and c.active == true,
      where: ilike(c.name, ^"%#{search_term}%"),
      limit: 10,
      order_by: [asc: c.name]

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

  def duplicate_character(%Character{} = character, user) do
    attrs = Map.from_struct(character)
    |> Map.delete(:id)
    |> Map.delete(:__meta__)
    |> Map.delete(:created_at)
    |> Map.delete(:updated_at)
    |> Map.put(:name, "#{character.name} (Copy)")
    |> Map.put(:user_id, user.id)

    create_character(attrs)
  end
end