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
        preload: [:faction]

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

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from j in query, where: j.id in ^ids
      else
        query
      end

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

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from j in count_query, where: j.id in ^ids
      else
        count_query
      end

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

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

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
    |> preload(:faction)
    |> Repo.get!(id)
  end

  def get_juncture(id) do
    Juncture
    |> preload(:faction)
    |> Repo.get(id)
  end

  def create_juncture(attrs \\ %{}) do
    %Juncture{}
    |> Juncture.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, juncture} ->
        juncture = Repo.preload(juncture, :faction)
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
        juncture = Repo.preload(juncture, :faction, force: true)
        broadcast_change(juncture, :update)
        {:ok, juncture}

      error ->
        error
    end
  end

  def delete_juncture(%Juncture{} = juncture) do
    juncture
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete)
  end
end
