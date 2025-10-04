defmodule ShotElixir.Factions do
  @moduledoc """
  The Factions context for managing campaign organizations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Factions.Faction
  use ShotElixir.Models.Broadcastable

  def list_factions(campaign_id) do
    query =
      from f in Faction,
        where: f.campaign_id == ^campaign_id and f.active == true,
        order_by: [asc: fragment("lower(?)", f.name)]

    Repo.all(query)
  end

  def list_campaign_factions(campaign_id, params \\ %{}, _current_user \\ nil) do
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

    # Base query with minimal fields for performance
    query =
      from f in Faction,
        where: f.campaign_id == ^campaign_id,
        select: [
          :id,
          :name,
          :description,
          :created_at,
          :updated_at,
          :active
        ]

    # Apply basic filters
    query =
      if params["id"] do
        from f in query, where: f.id == ^params["id"]
      else
        query
      end

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from f in query, where: f.id in ^ids
      else
        query
      end

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from f in query, where: ilike(f.name, ^search_term)
      else
        query
      end

    # Visibility filtering
    query = apply_visibility_filter(query, params)

    # Character filtering (factions containing specific characters)
    query =
      if params["character_id"] do
        from f in query,
          join: c in "characters",
          on: c.faction_id == f.id,
          where: c.id == ^params["character_id"]
      else
        query
      end

    # Vehicle filtering (factions containing specific vehicles)
    query =
      if params["vehicle_id"] do
        from f in query,
          join: v in "vehicles",
          on: v.faction_id == f.id,
          where: v.id == ^params["vehicle_id"]
      else
        query
      end

    # Juncture filtering (factions containing specific junctures)
    query =
      if params["juncture_id"] do
        from f in query,
          join: j in "junctures",
          on: j.faction_id == f.id,
          where: j.id == ^params["juncture_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query = from f in Faction, where: f.campaign_id == ^campaign_id

    # Apply same filters to count query
    count_query =
      if params["id"] do
        from f in count_query, where: f.id == ^params["id"]
      else
        count_query
      end

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from f in count_query, where: f.id in ^ids
      else
        count_query
      end

    count_query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from f in count_query, where: ilike(f.name, ^search_term)
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)

    count_query =
      if params["character_id"] do
        from f in count_query,
          join: c in "characters",
          on: c.faction_id == f.id,
          where: c.id == ^params["character_id"]
      else
        count_query
      end

    count_query =
      if params["vehicle_id"] do
        from f in count_query,
          join: v in "vehicles",
          on: v.faction_id == f.id,
          where: v.id == ^params["vehicle_id"]
      else
        count_query
      end

    count_query =
      if params["juncture_id"] do
        from f in count_query,
          join: j in "junctures",
          on: j.faction_id == f.id,
          where: j.id == ^params["juncture_id"]
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Apply pagination
    factions =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Return factions with pagination metadata
    %{
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
        from f in query, where: f.active == false

      "all" ->
        query

      _ ->
        # Default to visible (active) only
        from f in query, where: f.active == true
    end
  end

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [f], [
          {^order, fragment("LOWER(?)", f.name)},
          {:asc, f.id}
        ])

      "created_at" ->
        order_by(query, [f], [{^order, f.created_at}, {:asc, f.id}])

      "updated_at" ->
        order_by(query, [f], [{^order, f.updated_at}, {:asc, f.id}])

      _ ->
        order_by(query, [f], desc: f.created_at, asc: f.id)
    end
  end

  def get_faction!(id), do: Repo.get!(Faction, id)
  def get_faction(id), do: Repo.get(Faction, id)

  def create_faction(attrs \\ %{}) do
    %Faction{}
    |> Faction.changeset(attrs)
    |> Repo.insert()
    |> broadcast_result(:insert)
  end

  def update_faction(%Faction{} = faction, attrs) do
    faction
    |> Faction.changeset(attrs)
    |> Repo.update()
    |> broadcast_result(:update)
  end

  def delete_faction(%Faction{} = faction) do
    faction
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete)
  end
end
