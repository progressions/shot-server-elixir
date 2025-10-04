defmodule ShotElixir.Sites do
  @moduledoc """
  The Sites context for managing locations and attunements in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Sites.{Site, Attunement}
  use ShotElixir.Models.Broadcastable

  def list_sites(campaign_id) do
    query =
      from s in Site,
        where: s.campaign_id == ^campaign_id and s.active == true,
        order_by: [asc: fragment("lower(?)", s.name)],
        preload: [:faction, :juncture]

    Repo.all(query)
  end

  def list_campaign_sites(campaign_id, params \\ %{}, _current_user \\ nil) do
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
      from s in Site,
        where: s.campaign_id == ^campaign_id,
        select: [
          :id,
          :name,
          :description,
          :faction_id,
          :juncture_id,
          :created_at,
          :updated_at,
          :active
        ]

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

    # Faction filtering - handle "__NONE__" special case
    query =
      if params["faction_id"] do
        if params["faction_id"] == "__NONE__" do
          from s in query, where: is_nil(s.faction_id)
        else
          from s in query, where: s.faction_id == ^params["faction_id"]
        end
      else
        query
      end

    # Juncture filtering - handle "__NONE__" special case
    query =
      if params["juncture_id"] do
        if params["juncture_id"] == "__NONE__" do
          from s in query, where: is_nil(s.juncture_id)
        else
          from s in query, where: s.juncture_id == ^params["juncture_id"]
        end
      else
        query
      end

    # Visibility filtering
    query = apply_visibility_filter(query, params)

    # Character filtering (sites with attunements to specific character)
    query =
      if params["character_id"] do
        from s in query,
          join: a in "attunements",
          on: a.site_id == s.id,
          where: a.character_id == ^params["character_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query = from s in Site, where: s.campaign_id == ^campaign_id

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
      if params["faction_id"] do
        if params["faction_id"] == "__NONE__" do
          from s in count_query, where: is_nil(s.faction_id)
        else
          from s in count_query, where: s.faction_id == ^params["faction_id"]
        end
      else
        count_query
      end

    count_query =
      if params["juncture_id"] do
        if params["juncture_id"] == "__NONE__" do
          from s in count_query, where: is_nil(s.juncture_id)
        else
          from s in count_query, where: s.juncture_id == ^params["juncture_id"]
        end
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)

    count_query =
      if params["character_id"] do
        from s in count_query,
          join: a in "attunements",
          on: a.site_id == s.id,
          where: a.character_id == ^params["character_id"]
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Get factions for filtering UI
    factions_query =
      from s in Site,
        where: s.campaign_id == ^campaign_id and s.active == true,
        join: f in "factions",
        on: s.faction_id == f.id,
        select: %{id: f.id, name: f.name},
        distinct: [f.id, f.name],
        order_by: [asc: fragment("LOWER(?)", f.name)]

    factions =
      factions_query
      |> Repo.all()
      |> Enum.map(fn entry ->
        Map.update(entry, :id, nil, fn id -> normalize_uuid(id) end)
      end)

    # Apply pagination
    sites =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Return sites with pagination metadata and factions
    %{
      sites: sites,
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
    |> Enum.map(&normalize_uuid/1)
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: Enum.map(ids_param, &normalize_uuid/1)
  defp parse_ids(_), do: []

  defp apply_visibility_filter(query, params) do
    case params["visibility"] do
      "hidden" ->
        from s in query, where: s.active == false

      "all" ->
        query

      _ ->
        # Default to visible (active) only
        from s in query, where: s.active == true
    end
  end

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [s], [
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

  def get_site!(id) do
    Site
    |> preload([:faction, :juncture, attunements: [:character]])
    |> Repo.get!(id)
  end

  def get_site(id) do
    Site
    |> preload([:faction, :juncture, attunements: [:character]])
    |> Repo.get(id)
  end

  def create_site(attrs \\ %{}) do
    %Site{}
    |> Site.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, site} ->
        site = Repo.preload(site, [:faction, :juncture])
        broadcast_change(site, :insert)
        {:ok, site}

      error -> error
    end
  end

  def update_site(%Site{} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, site} ->
        site = Repo.preload(site, [:faction, :juncture], force: true)
        broadcast_change(site, :update)
        {:ok, site}

      error -> error
    end
  end

  def delete_site(%Site{} = site) do
    site
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete)
  end

  def create_attunement(attrs \\ %{}) do
    %Attunement{}
    |> Attunement.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, attunement} ->
        attunement = Repo.preload(attunement, [:character, :site])
        broadcast_site_update(attunement.site_id)
        {:ok, attunement}

      error -> error
    end
  end

  def delete_attunement(%Attunement{} = attunement) do
    attunement
    |> Repo.delete()
    |> case do
      {:ok, attunement} = result ->
        broadcast_site_update(attunement.site_id)
        result

      error ->
        error
    end
  end

  def get_attunement_by_character_and_site(character_id, site_id) do
    Attunement
    |> where([a], a.character_id == ^character_id and a.site_id == ^site_id)
    |> Repo.one()
  end

  def list_site_attunements(site_id) do
    query =
      from a in Attunement,
        where: a.site_id == ^site_id,
        preload: [:character]

    Repo.all(query)
  end

  defp normalize_uuid(nil), do: nil

  defp normalize_uuid(id) when is_binary(id) and byte_size(id) == 16 do
    case Ecto.UUID.load(id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_uuid(id), do: id

  defp broadcast_site_update(nil), do: :ok

  defp broadcast_site_update(site_id) do
    case get_site(site_id) do
      nil -> :ok
      site ->
        site
        |> Repo.preload([:faction, :juncture], force: true)
        |> broadcast_change(:update)
    end
  end
end
