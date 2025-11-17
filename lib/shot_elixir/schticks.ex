defmodule ShotElixir.Schticks do
  @moduledoc """
  The Schticks context for managing character abilities.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Schticks.Schtick
  alias ShotElixir.ImageLoader
  use ShotElixir.Models.Broadcastable

  def list_campaign_schticks(campaign_id, params \\ %{}, _current_user \\ nil) do
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
      from s in Schtick,
        where: s.campaign_id == ^campaign_id

    # Apply basic filters
    query =
      if params["id"] do
        from s in query, where: s.id == ^params["id"]
      else
        query
      end

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from s in query, where: s.id in ^ids
      else
        query
      end

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from s in query, where: ilike(s.name, ^search_term)
      else
        query
      end

    # Category filtering - handle "__NONE__" special case
    query =
      if params["category"] && params["category"] != "" do
        if params["category"] == "__NONE__" do
          from s in query, where: is_nil(s.category)
        else
          from s in query, where: s.category == ^params["category"]
        end
      else
        query
      end

    # Path filtering - handle "__NONE__" special case
    query =
      if params["path"] && params["path"] != "" do
        if params["path"] == "__NONE__" do
          from s in query, where: is_nil(s.path)
        else
          from s in query, where: s.path == ^params["path"]
        end
      else
        query
      end

    # Visibility filtering
    query = apply_visibility_filter(query, params)

    # Character filtering
    query =
      if params["character_id"] do
        from s in query,
          join: cs in "character_schticks",
          on: cs.schtick_id == s.id,
          where: cs.character_id == ^params["character_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query = from s in Schtick, where: s.campaign_id == ^campaign_id

    # Apply same filters to count query
    count_query =
      if params["id"] do
        from s in count_query, where: s.id == ^params["id"]
      else
        count_query
      end

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from s in count_query, where: s.id in ^ids
      else
        count_query
      end

    count_query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from s in count_query, where: ilike(s.name, ^search_term)
      else
        count_query
      end

    count_query =
      if params["category"] && params["category"] != "" do
        if params["category"] == "__NONE__" do
          from s in count_query, where: is_nil(s.category)
        else
          from s in count_query, where: s.category == ^params["category"]
        end
      else
        count_query
      end

    count_query =
      if params["path"] && params["path"] != "" do
        if params["path"] == "__NONE__" do
          from s in count_query, where: is_nil(s.path)
        else
          from s in count_query, where: s.path == ^params["path"]
        end
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)

    count_query =
      if params["character_id"] do
        from s in count_query,
          join: cs in "character_schticks",
          on: cs.schtick_id == s.id,
          where: cs.character_id == ^params["character_id"]
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Get categories and paths for filtering UI
    categories_query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.active == true,
        select: s.category,
        distinct: true

    categories =
      categories_query
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    paths_query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.active == true,
        select: s.path,
        distinct: true

    paths =
      paths_query
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    # Apply pagination
    schticks =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Load image URLs for all schticks efficiently
    schticks_with_images = ImageLoader.load_image_urls(schticks, "Schtick")

    # Return schticks with pagination metadata
    %{
      schticks: schticks_with_images,
      categories: categories,
      paths: paths,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      },
      is_autocomplete: params["autocomplete"] == "true" || params["autocomplete"] == true
    }
  end

  # Legacy function for backward compatibility
  def list_schticks(campaign_id, filters \\ %{}) do
    query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.active == true,
        order_by: [asc: s.category, asc: fragment("lower(?)", s.name)]

    query = apply_legacy_filters(query, filters)

    query
    |> preload_prerequisites()
    |> Repo.all()
  end

  defp apply_legacy_filters(query, filters) do
    query
    |> filter_by_category(filters["category"])
    |> filter_by_path(filters["path"])
  end

  defp filter_by_category(query, nil), do: query

  defp filter_by_category(query, category) do
    from s in query, where: s.category == ^category
  end

  defp filter_by_path(query, nil), do: query

  defp filter_by_path(query, path) do
    from s in query, where: s.path == ^path
  end

  defp apply_visibility_filter(query, _params) do
    # Always show only active schticks
    from s in query, where: s.active == true
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [s], [
          {^order, fragment("LOWER(?)", s.name)},
          {:asc, s.id}
        ])

      "category" ->
        order_by(query, [s], [
          {^order, fragment("LOWER(?)", s.category)},
          {^order, fragment("LOWER(?)", s.name)},
          {:asc, s.id}
        ])

      "path" ->
        order_by(query, [s], [
          {^order, fragment("LOWER(?)", s.path)},
          {^order, fragment("LOWER(?)", s.name)},
          {:asc, s.id}
        ])

      "created_at" ->
        order_by(query, [s], [{^order, s.created_at}, {:asc, s.id}])

      "updated_at" ->
        order_by(query, [s], [{^order, s.updated_at}, {:asc, s.id}])

      _ ->
        order_by(query, [s], desc: s.created_at, asc: s.id)
    end
  end

  defp preload_prerequisites(query) do
    from s in query,
      left_join: p in Schtick,
      on: s.prerequisite_id == p.id,
      preload: [prerequisite: p]
  end

  def get_schtick!(id) do
    Schtick
    |> preload(:prerequisite)
    |> Repo.get!(id)
    |> ImageLoader.load_image_url("Schtick")
  end

  def get_schtick(id) do
    Schtick
    |> preload(:prerequisite)
    |> Repo.get(id)
    |> ImageLoader.load_image_url("Schtick")
  end

  def create_schtick(attrs \\ %{}) do
    %Schtick{}
    |> Schtick.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schtick} ->
        schtick = Repo.preload(schtick, :prerequisite)
        broadcast_change(schtick, :insert)
        {:ok, schtick}

      error ->
        error
    end
  end

  def update_schtick(%Schtick{} = schtick, attrs) do
    schtick
    |> Schtick.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, schtick} ->
        schtick = Repo.preload(schtick, :prerequisite, force: true)
        broadcast_change(schtick, :update)
        {:ok, schtick}

      error ->
        error
    end
  end

  def delete_schtick(%Schtick{} = schtick) do
    # Check if any schticks depend on this one as a prerequisite
    dependent_count =
      from(s in Schtick,
        where: s.prerequisite_id == ^schtick.id and s.active == true,
        select: count(s.id)
      )
      |> Repo.one()

    cond do
      dependent_count > 0 ->
        {:error, :has_dependents}

      true ->
        schtick
        |> Ecto.Changeset.change(active: false)
        |> Repo.update()
        |> case do
          {:ok, schtick} = result ->
            broadcast_change(schtick, :delete)
            result

          error ->
            error
        end
    end
  end

  def get_prerequisite_tree(schtick_id) do
    with schtick when not is_nil(schtick) <- get_schtick(schtick_id) do
      build_tree(schtick)
    else
      nil -> {:error, :not_found}
    end
  end

  defp build_tree(nil), do: nil

  defp build_tree(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      category: schtick.category,
      prerequisite: build_tree(schtick.prerequisite)
    }
  end

  # Get categories for a campaign
  def get_categories(campaign_id, params \\ %{}) do
    query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.active == true,
        select: s.category,
        distinct: true

    categories =
      query
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    core_categories_query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.active == true and s.path == "Core",
        select: s.category,
        distinct: true

    core_categories =
      core_categories_query
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    general_categories = categories -- core_categories

    # Apply search filter if provided
    {general_categories, core_categories} =
      if params["search"] do
        search = String.downcase(params["search"])

        general_filtered =
          Enum.filter(general_categories, fn cat ->
            String.contains?(String.downcase(cat), search)
          end)

        core_filtered =
          Enum.filter(core_categories, fn cat ->
            String.contains?(String.downcase(cat), search)
          end)

        {general_filtered, core_filtered}
      else
        {general_categories, core_categories}
      end

    %{
      general: Enum.sort(general_categories),
      core: Enum.sort(core_categories)
    }
  end

  # Get paths for a campaign
  def get_paths(campaign_id, params \\ %{}) do
    query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.active == true

    query =
      if params["category"] do
        from s in query, where: s.category == ^params["category"]
      else
        query
      end

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from s in query, where: ilike(s.path, ^search_term)
      else
        query
      end

    paths =
      query
      |> select([s], s.path)
      |> distinct([s], s.path)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort_by(&String.downcase/1)

    %{paths: paths}
  end

  # Batch fetch for specific IDs
  def get_schticks_batch(campaign_id, ids, params \\ %{}) do
    per_page =
      case params["per_page"] do
        nil -> 200
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

    query =
      from s in Schtick,
        where: s.campaign_id == ^campaign_id and s.id in ^ids,
        limit: ^per_page,
        offset: ^offset

    schticks =
      query
      |> Repo.all()
      |> Enum.map(&ImageLoader.load_image_url(&1, "Schtick"))

    # Get total count for this batch
    total_count =
      from(s in Schtick,
        where: s.campaign_id == ^campaign_id and s.id in ^ids,
        select: count(s.id)
      )
      |> Repo.one()

    %{
      schticks: schticks,
      categories: [],
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      }
    }
  end

  def categories, do: Schtick.categories()
  def paths, do: Schtick.paths()
end
