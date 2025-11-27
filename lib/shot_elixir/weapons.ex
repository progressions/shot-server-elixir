defmodule ShotElixir.Weapons do
  @moduledoc """
  The Weapons context for managing weapons in campaigns.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias ShotElixir.Repo
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.ImageLoader
  use ShotElixir.Models.Broadcastable

  def list_weapons(campaign_id, filters \\ %{}) do
    per_page = max(parse_int(filters["per_page"], 15), 1)
    page = parse_int(filters["page"], 1)
    offset = max(page - 1, 0) * per_page

    query =
      from w in Weapon,
        where: w.campaign_id == ^campaign_id and w.active == true

    filtered_query = apply_filters(query, filters)
    ordered_query = order_by(filtered_query, [w], fragment("lower(?)", w.name))

    total_count = Repo.aggregate(ordered_query, :count, :id)

    categories =
      filtered_query
      |> select([w], w.category)
      |> where([w], not is_nil(w.category) and w.category != "")
      |> distinct(true)
      |> Repo.all()
      |> Enum.sort()

    junctures =
      filtered_query
      |> select([w], w.juncture)
      |> where([w], not is_nil(w.juncture) and w.juncture != "")
      |> distinct(true)
      |> Repo.all()
      |> Enum.sort()

    weapons =
      ordered_query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Load image URLs for all weapons efficiently
    weapons_with_images = ImageLoader.load_image_urls(weapons, "Weapon")

    %{
      weapons: weapons_with_images,
      categories: categories,
      junctures: junctures,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: total_pages(total_count, per_page)
      }
    }
  end

  defp apply_filters(query, filters) do
    query
    |> filter_by_ids(filters["ids"], Map.has_key?(filters, "ids"))
    |> filter_by_category(filters["category"])
    |> filter_by_juncture(filters["juncture"])
  end

  # If ids param not present at all, don't filter
  defp filter_by_ids(query, _ids, false), do: query
  # If ids param present but nil or empty list, return no results
  defp filter_by_ids(query, nil, true), do: from(w in query, where: false)
  defp filter_by_ids(query, [], true), do: from(w in query, where: false)
  # If ids param present with values, filter to those IDs
  defp filter_by_ids(query, ids, true) when is_list(ids) do
    from(w in query, where: w.id in ^ids)
  end

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, ""), do: query

  defp filter_by_category(query, category) do
    from w in query, where: w.category == ^category
  end

  defp filter_by_juncture(query, nil), do: query
  defp filter_by_juncture(query, ""), do: query

  defp filter_by_juncture(query, juncture) do
    from w in query, where: w.juncture == ^juncture
  end

  def get_weapon!(id) do
    Repo.get!(Weapon, id)
    |> ImageLoader.load_image_url("Weapon")
  end

  def get_weapon(id) do
    Repo.get(Weapon, id)
    |> ImageLoader.load_image_url("Weapon")
  end

  def get_weapon_by_name(campaign_id, name) do
    Repo.get_by(Weapon, campaign_id: campaign_id, name: name)
  end

  def create_weapon(attrs \\ %{}) do
    %Weapon{}
    |> Weapon.changeset(attrs)
    |> Repo.insert()
    |> broadcast_result(:insert)
  end

  def update_weapon(%Weapon{} = weapon, attrs) do
    weapon
    |> Weapon.changeset(attrs)
    |> Repo.update()
    |> broadcast_result(:update)
  end

  def delete_weapon(%Weapon{} = weapon) do
    weapon
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete)
  end

  def weapon_categories do
    ["guns", "melee", "heavy", "improvised", "explosive"]
  end

  def junctures do
    ["Ancient", "1850s", "Contemporary", "Future"]
  end

  def list_categories(campaign_id), do: list_categories(campaign_id, nil)

  def list_categories(campaign_id, search) do
    Weapon
    |> where([w], w.campaign_id == ^campaign_id)
    |> select([w], w.category)
    |> where([w], not is_nil(w.category) and w.category != "")
    |> distinct(true)
    |> Repo.all()
    |> maybe_filter_by_search(search)
    |> Enum.sort()
  end

  def list_junctures(campaign_id), do: list_junctures(campaign_id, nil)

  def list_junctures(campaign_id, search) do
    Weapon
    |> where([w], w.campaign_id == ^campaign_id)
    |> select([w], w.juncture)
    |> where([w], not is_nil(w.juncture) and w.juncture != "")
    |> distinct(true)
    |> Repo.all()
    |> maybe_filter_by_search(search)
    |> Enum.sort()
  end

  def get_weapons_batch(campaign_id, ids) when is_list(ids) do
    Weapon
    |> where([w], w.campaign_id == ^campaign_id and w.id in ^ids)
    |> Repo.all()
  end

  def remove_image(%Weapon{} = weapon) do
    weapon
    |> Changeset.change(image_url: nil)
    |> Repo.update()
    |> broadcast_result(:update)
  end

  defp maybe_filter_by_search(values, nil), do: values

  defp maybe_filter_by_search(values, search) when is_binary(search) do
    search_downcase = String.downcase(search)

    Enum.filter(values, fn value ->
      value
      |> String.downcase()
      |> String.contains?(search_downcase)
    end)
  end

  defp maybe_filter_by_search(values, _), do: values

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(_, default), do: default

  defp total_pages(0, _per_page), do: 0

  defp total_pages(total_count, per_page) when per_page > 0 do
    div(total_count + per_page - 1, per_page)
  end
end
