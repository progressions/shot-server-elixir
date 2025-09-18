defmodule ShotElixir.Weapons do
  @moduledoc """
  The Weapons context for managing weapons in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Weapons.Weapon

  def list_weapons(campaign_id, filters \\ %{}) do
    query =
      from w in Weapon,
        where: w.campaign_id == ^campaign_id and w.active == true,
        order_by: [asc: fragment("lower(?)", w.name)]

    query = apply_filters(query, filters)
    Repo.all(query)
  end

  defp apply_filters(query, filters) do
    query
    |> filter_by_category(filters["category"])
    |> filter_by_juncture(filters["juncture"])
  end

  defp filter_by_category(query, nil), do: query

  defp filter_by_category(query, category) do
    from w in query, where: w.category == ^category
  end

  defp filter_by_juncture(query, nil), do: query

  defp filter_by_juncture(query, juncture) do
    from w in query, where: w.juncture == ^juncture
  end

  def get_weapon!(id), do: Repo.get!(Weapon, id)
  def get_weapon(id), do: Repo.get(Weapon, id)

  def create_weapon(attrs \\ %{}) do
    %Weapon{}
    |> Weapon.changeset(attrs)
    |> Repo.insert()
  end

  def update_weapon(%Weapon{} = weapon, attrs) do
    weapon
    |> Weapon.changeset(attrs)
    |> Repo.update()
  end

  def delete_weapon(%Weapon{} = weapon) do
    weapon
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def weapon_categories do
    ["guns", "melee", "heavy", "improvised", "explosive"]
  end

  def junctures do
    ["Ancient", "1850s", "Contemporary", "Future"]
  end
end
