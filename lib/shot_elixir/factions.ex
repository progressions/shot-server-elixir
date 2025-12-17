defmodule ShotElixir.Factions do
  @moduledoc """
  The Factions context for managing campaign organizations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Factions.Faction
  alias ShotElixir.ImageLoader
  use ShotElixir.Models.Broadcastable

  def list_factions(campaign_id) do
    query =
      from f in Faction,
        where: f.campaign_id == ^campaign_id and f.active == true,
        order_by: [asc: fragment("lower(?)", f.name)]

    Repo.all(query)
  end

  @doc """
  Get factions by a list of IDs, ordered by name (case-insensitive).
  Returns only id and name fields like Rails FactionLiteSerializer.
  """
  def get_factions_by_ids(faction_ids) when is_list(faction_ids) do
    # Filter out nils and empty values
    ids = faction_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if Enum.empty?(ids) do
      []
    else
      from(f in Faction,
        where: f.id in ^ids,
        select: %{id: f.id, name: f.name},
        order_by: [asc: fragment("LOWER(?)", f.name)]
      )
      |> Repo.all()
    end
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

    # Base query
    query =
      from f in Faction,
        where: f.campaign_id == ^campaign_id

    # Apply basic filters
    query =
      if params["id"] do
        from f in query, where: f.id == ^params["id"]
      else
        query
      end

    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))

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
      if params["character_id"] && params["character_id"] != "" do
        from f in query,
          join: c in "characters",
          on: c.faction_id == f.id,
          where: c.id == ^params["character_id"]
      else
        query
      end

    # Vehicle filtering (factions containing specific vehicles)
    query =
      if params["vehicle_id"] && params["vehicle_id"] != "" do
        from f in query,
          join: v in "vehicles",
          on: v.faction_id == f.id,
          where: v.id == ^params["vehicle_id"]
      else
        query
      end

    # Juncture filtering (factions containing specific junctures)
    query =
      if params["juncture_id"] && params["juncture_id"] != "" do
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
      if params["character_id"] && params["character_id"] != "" do
        from f in count_query,
          join: c in "characters",
          on: c.faction_id == f.id,
          where: c.id == ^params["character_id"]
      else
        count_query
      end

    count_query =
      if params["vehicle_id"] && params["vehicle_id"] != "" do
        from f in count_query,
          join: v in "vehicles",
          on: v.faction_id == f.id,
          where: v.id == ^params["vehicle_id"]
      else
        count_query
      end

    count_query =
      if params["juncture_id"] && params["juncture_id"] != "" do
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
      |> preload([:characters, :vehicles, :sites, :parties, :junctures])
      |> Repo.all()

    # Load image URLs for all factions efficiently
    factions_with_images = ImageLoader.load_image_urls(factions, "Faction")

    # Return factions with pagination metadata
    %{
      factions: factions_with_images,
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
  defp apply_ids_filter(query, nil, true), do: from(f in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(f in query, where: false)
  # If ids param present with values, filter to those IDs
  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(f in query, where: f.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(f in query, where: false),
      else: from(f in query, where: f.id in ^parsed)
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

  def get_faction!(id) do
    Repo.get!(Faction, id)
    |> Repo.preload([:characters, :vehicles, :sites, :parties, :junctures, :image_positions])
    |> ImageLoader.load_image_url("Faction")
  end

  def get_faction(id) do
    case Repo.get(Faction, id) do
      nil ->
        nil

      faction ->
        faction
        |> Repo.preload([:characters, :vehicles, :sites, :parties, :junctures, :image_positions])
        |> ImageLoader.load_image_url("Faction")
    end
  end

  def create_faction(attrs \\ %{}) do
    result =
      %Faction{}
      |> Faction.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(:insert)

    # Track onboarding milestone
    case result do
      {:ok, faction} ->
        ShotElixir.Models.Concerns.OnboardingTrackable.track_milestone(faction)
        {:ok, faction}

      error ->
        error
    end
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
