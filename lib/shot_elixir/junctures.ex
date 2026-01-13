defmodule ShotElixir.Junctures do
  @moduledoc """
  The Junctures context for managing time periods in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.ImageLoader
  use ShotElixir.Models.Broadcastable

  def list_junctures(campaign_id) do
    query =
      from j in Juncture,
        where: j.campaign_id == ^campaign_id and j.active == true,
        order_by: [asc: fragment("lower(?)", j.name)],
        preload: [:faction, :image_positions]

    Repo.all(query)
  end

  def list_campaign_junctures(campaign_id, params \\ %{}, _current_user \\ nil) do
    # Get pagination parameters - handle both string and integer params
    per_page =
      case params["per_page"] do
        nil -> 15
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    page =
      case params["page"] do
        nil -> 1
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    offset = (page - 1) * per_page

    # Base query
    query =
      from j in Juncture,
        where: j.campaign_id == ^campaign_id

    # Apply basic filters
    query =
      if params["id"] do
        from j in query, where: j.id == ^params["id"]
      else
        query
      end

    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from j in query, where: ilike(j.name, ^search_term)
      else
        query
      end

    # Faction filtering
    query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from j in query, where: is_nil(j.faction_id)
        else
          from j in query, where: j.faction_id == ^params["faction_id"]
        end
      else
        query
      end

    # Visibility filtering
    query = apply_visibility_filter(query, params)
    query = apply_at_a_glance_filter(query, params)

    # Character filtering (junctures containing specific characters)
    query =
      if params["character_id"] && params["character_id"] != "" do
        from j in query,
          join: c in "characters",
          on: c.juncture_id == j.id,
          where: c.id == ^params["character_id"]
      else
        query
      end

    # Vehicle filtering (junctures containing specific vehicles)
    query =
      if params["vehicle_id"] && params["vehicle_id"] != "" do
        from j in query,
          join: v in "vehicles",
          on: v.juncture_id == j.id,
          where: v.id == ^params["vehicle_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query = from j in Juncture, where: j.campaign_id == ^campaign_id

    # Apply same filters to count query
    count_query =
      if params["id"] do
        from j in count_query, where: j.id == ^params["id"]
      else
        count_query
      end

    count_query = apply_ids_filter(count_query, params["ids"], Map.has_key?(params, "ids"))

    count_query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from j in count_query, where: ilike(j.name, ^search_term)
      else
        count_query
      end

    count_query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from j in count_query, where: is_nil(j.faction_id)
        else
          from j in count_query, where: j.faction_id == ^params["faction_id"]
        end
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)
    count_query = apply_at_a_glance_filter(count_query, params)

    count_query =
      if params["character_id"] && params["character_id"] != "" do
        from j in count_query,
          join: c in "characters",
          on: c.juncture_id == j.id,
          where: c.id == ^params["character_id"]
      else
        count_query
      end

    count_query =
      if params["vehicle_id"] && params["vehicle_id"] != "" do
        from j in count_query,
          join: v in "vehicles",
          on: v.juncture_id == j.id,
          where: v.id == ^params["vehicle_id"]
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Apply pagination
    junctures =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> preload([:faction, :image_positions, :characters, :vehicles])
      |> Repo.all()

    # Load image URLs for all junctures efficiently
    junctures_with_images = ImageLoader.load_image_urls(junctures, "Juncture")

    # Fetch factions for the junctures
    faction_ids = junctures |> Enum.map(& &1.faction_id) |> Enum.uniq() |> Enum.reject(&is_nil/1)

    factions =
      if Enum.any?(faction_ids) do
        from(f in "factions",
          where: fragment("? = ANY(?)", f.id, type(^faction_ids, {:array, :binary_id})),
          select: %{id: type(f.id, :binary_id), name: f.name},
          order_by: [asc: fragment("LOWER(?)", f.name)]
        )
        |> Repo.all()
        |> Enum.map(fn faction ->
          %{id: Ecto.UUID.cast!(faction.id), name: faction.name}
        end)
      else
        []
      end

    # Return junctures with pagination metadata
    %{
      junctures: junctures_with_images,
      factions: factions,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      },
      is_autocomplete: params["autocomplete"] == "true" || params["autocomplete"] == true
    }
  end

  # If ids param not present at all, don't filter
  defp apply_ids_filter(query, _ids, false), do: query
  # If ids param present but nil or empty list, return no results
  defp apply_ids_filter(query, nil, true), do: from(j in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(j in query, where: false)
  # If ids param present with values, filter to those IDs
  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(j in query, where: j.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(j in query, where: false),
      else: from(j in query, where: j.id in ^parsed)
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_visibility_filter(query, params) do
    case params["visibility"] do
      "hidden" ->
        from j in query, where: j.active == false

      "all" ->
        query

      _ ->
        # Default to visible (active) only
        from j in query, where: j.active == true
    end
  end

  defp apply_at_a_glance_filter(query, params) do
    case at_a_glance_param(params) do
      "true" ->
        from j in query, where: j.at_a_glance == true

      true ->
        from j in query, where: j.at_a_glance == true

      _ ->
        query
    end
  end

  defp at_a_glance_param(params) do
    Map.get(params, "at_a_glance") || Map.get(params, "at_a_glace")
  end

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if String.downcase(params["order"] || "") == "asc", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [j], [
          {^order, fragment("LOWER(?)", j.name)},
          {:asc, j.id}
        ])

      "created_at" ->
        order_by(query, [j], [{^order, j.created_at}, {:asc, j.id}])

      "updated_at" ->
        order_by(query, [j], [{^order, j.updated_at}, {:asc, j.id}])

      _ ->
        order_by(query, [j], desc: j.created_at, asc: j.id)
    end
  end

  def get_juncture!(id) do
    Juncture
    |> preload([:faction, :image_positions])
    |> Repo.get!(id)
  end

  def get_juncture(id) do
    Juncture
    |> preload([:faction, :image_positions])
    |> Repo.get(id)
  end

  def get_juncture_with_preloads(id) do
    Juncture
    |> preload([:faction, :image_positions, :characters, :vehicles])
    |> Repo.get(id)
  end

  def create_juncture(attrs \\ %{}) do
    %Juncture{}
    |> Juncture.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, juncture} ->
        juncture = Repo.preload(juncture, [:faction, :image_positions])
        broadcast_change(juncture, :insert)
        {:ok, juncture}

      error ->
        error
    end
  end

  def update_juncture(%Juncture{} = juncture, attrs) do
    juncture
    |> Juncture.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, juncture} ->
        # Sync character junctures if character_ids is provided
        character_ids =
          cond do
            Map.has_key?(attrs, "character_ids") -> Map.get(attrs, "character_ids")
            Map.has_key?(attrs, :character_ids) -> Map.get(attrs, :character_ids)
            true -> :no_update
          end

        if character_ids != :no_update do
          sync_character_junctures(juncture, character_ids)
        end

        # Sync site junctures if site_ids is provided
        site_ids =
          cond do
            Map.has_key?(attrs, "site_ids") -> Map.get(attrs, "site_ids")
            Map.has_key?(attrs, :site_ids) -> Map.get(attrs, :site_ids)
            true -> :no_update
          end

        if site_ids != :no_update do
          sync_site_junctures(juncture, site_ids)
        end

        juncture = Repo.preload(juncture, [:faction, :characters, :image_positions], force: true)
        broadcast_change(juncture, :update)
        {:ok, juncture}

      error ->
        error
    end
  end

  # Syncs juncture character assignments to match the provided character_ids list.
  # Removes juncture from characters not in the list and adds juncture to new ones.
  defp sync_character_junctures(juncture, character_ids) when is_list(character_ids) do
    alias ShotElixir.Characters.Character

    # Get current character_ids for this juncture
    current_character_ids =
      from(c in Character, where: c.juncture_id == ^juncture.id, select: c.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    # Normalize incoming character_ids to strings
    new_character_ids = Enum.map(character_ids, &to_string/1)

    # Find characters to add and remove
    to_add = new_character_ids -- current_character_ids
    to_remove = current_character_ids -- new_character_ids

    # Remove juncture from characters that are no longer in the list
    if Enum.any?(to_remove) do
      from(c in Character, where: c.id in ^to_remove)
      |> Repo.update_all(set: [juncture_id: nil])
    end

    # Add juncture to new characters
    if Enum.any?(to_add) do
      from(c in Character, where: c.id in ^to_add)
      |> Repo.update_all(set: [juncture_id: juncture.id])
    end

    juncture
  end

  defp sync_character_junctures(juncture, _), do: juncture

  # Syncs juncture site assignments to match the provided site_ids list.
  # Removes juncture from sites not in the list and adds juncture to new ones.
  defp sync_site_junctures(juncture, site_ids) when is_list(site_ids) do
    alias ShotElixir.Sites.Site

    current_site_ids =
      from(s in Site, where: s.juncture_id == ^juncture.id, select: s.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    new_site_ids = Enum.map(site_ids, &to_string/1)

    to_add = new_site_ids -- current_site_ids
    to_remove = current_site_ids -- new_site_ids

    if Enum.any?(to_remove) do
      from(s in Site, where: s.id in ^to_remove)
      |> Repo.update_all(set: [juncture_id: nil])
    end

    if Enum.any?(to_add) do
      from(s in Site, where: s.id in ^to_add)
      |> Repo.update_all(set: [juncture_id: juncture.id])
    end

    juncture
  end

  defp sync_site_junctures(juncture, _), do: juncture

  def delete_juncture(%Juncture{} = juncture) do
    juncture
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete)
  end

  def get_juncture_by_name(campaign_id, name) do
    Repo.get_by(Juncture, campaign_id: campaign_id, name: name)
  end
end
