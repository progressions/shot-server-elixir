defmodule ShotElixir.Weapons do
  @moduledoc """
  The Weapons context for managing weapons in campaigns.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias ShotElixir.Repo
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.ImageLoader
  alias ShotElixir.Slug
  alias ShotElixir.Workers.ImageCopyWorker
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
    |> filter_by_at_a_glance(filters)
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

  defp filter_by_at_a_glance(query, filters) do
    case Map.get(filters, "at_a_glance") do
      "true" ->
        from w in query, where: w.at_a_glance == true

      true ->
        from w in query, where: w.at_a_glance == true

      _ ->
        query
    end
  end

  def get_weapon!(id) do
    id
    |> Slug.extract_uuid()
    |> Repo.get!(Weapon)
    |> ImageLoader.load_image_url("Weapon")
  end

  def get_weapon(id) do
    id
    |> Slug.extract_uuid()
    |> Repo.get(Weapon)
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
    alias Ecto.Multi
    alias ShotElixir.Weapons.Carry
    alias ShotElixir.Media

    Multi.new()
    # Delete related records first
    |> Multi.delete_all(
      :delete_carries,
      from(c in Carry, where: c.weapon_id == ^weapon.id)
    )
    # Orphan associated images instead of deleting them
    |> Multi.update_all(
      :orphan_images,
      Media.orphan_images_query("Weapon", weapon.id),
      []
    )
    |> Multi.delete(:weapon, weapon)
    |> Multi.run(:broadcast, fn _repo, %{weapon: deleted_weapon} ->
      broadcast_change(deleted_weapon, :delete)
      {:ok, deleted_weapon}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{weapon: weapon}} -> {:ok, weapon}
      {:error, :weapon, changeset, _} -> {:error, changeset}
    end
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

  @doc """
  Duplicates a weapon, creating a new weapon with the same attributes.
  The new weapon has a unique name within the campaign.
  """
  def duplicate_weapon(%Weapon{} = weapon) do
    # Generate unique name for the duplicate
    unique_name = generate_unique_name(weapon.name, weapon.campaign_id)

    attrs =
      Map.from_struct(weapon)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:image_url)
      |> Map.delete(:campaign)
      |> Map.put(:name, unique_name)

    case create_weapon(attrs) do
      {:ok, new_weapon} ->
        queue_image_copy(weapon, new_weapon)
        {:ok, new_weapon}

      error ->
        error
    end
  end

  defp queue_image_copy(source, target) do
    %{
      "source_type" => "Weapon",
      "source_id" => source.id,
      "target_type" => "Weapon",
      "target_id" => target.id
    }
    |> ImageCopyWorker.new()
    |> Oban.insert()
  end

  @doc """
  Generates a unique name for a weapon within a campaign.
  Strips any existing trailing number suffix like " (1)", " (2)", etc.
  Then finds the next available number if the base name exists.
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)

    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if the base name exists
    case Repo.exists?(
           from w in Weapon, where: w.campaign_id == ^campaign_id and w.name == ^base_name
         ) do
      false ->
        base_name

      true ->
        # Find the next available number
        find_next_available_name(base_name, campaign_id, 1)
    end
  end

  def generate_unique_name(name, _campaign_id), do: name

  defp find_next_available_name(base_name, campaign_id, counter) do
    new_name = "#{base_name} (#{counter})"

    case Repo.exists?(
           from w in Weapon, where: w.campaign_id == ^campaign_id and w.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end
end
