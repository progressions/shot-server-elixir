defmodule ShotElixir.Sites do
  @moduledoc """
  The Sites context for managing locations and attunements in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Sites.{Site, Attunement}
  alias ShotElixir.ImageLoader
  alias ShotElixir.Workers.ImageCopyWorker
  use ShotElixir.Models.Broadcastable

  def list_sites(campaign_id) do
    query =
      from s in Site,
        where: s.campaign_id == ^campaign_id and s.active == true,
        order_by: [asc: fragment("lower(?)", s.name)],
        preload: [:faction, :juncture]

    query
    |> Repo.all()
    |> ImageLoader.load_image_urls("Site")
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

    # Base query
    query =
      from s in Site,
        where: s.campaign_id == ^campaign_id

    # Apply basic filters
    query =
      if params["id"] do
        from s in query, where: s.id == ^params["id"]
      else
        query
      end

    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from s in query, where: ilike(s.name, ^search_term)
      else
        query
      end

    # Faction filtering - handle "__NONE__" special case
    query =
      if params["faction_id"] && params["faction_id"] != "" do
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
      if params["juncture_id"] && params["juncture_id"] != "" do
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
      if params["character_id"] && params["character_id"] != "" do
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

    count_query = apply_ids_filter(count_query, params["ids"], Map.has_key?(params, "ids"))

    count_query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from s in count_query, where: ilike(s.name, ^search_term)
      else
        count_query
      end

    count_query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from s in count_query, where: is_nil(s.faction_id)
        else
          from s in count_query, where: s.faction_id == ^params["faction_id"]
        end
      else
        count_query
      end

    count_query =
      if params["juncture_id"] && params["juncture_id"] != "" do
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
      if params["character_id"] && params["character_id"] != "" do
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
      |> preload([:faction, :juncture, attunements: [:character]])
      |> Repo.all()

    # Load image URLs for all sites efficiently
    sites_with_images = ImageLoader.load_image_urls(sites, "Site")

    # Return sites with pagination metadata and factions
    %{
      sites: sites_with_images,
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
  defp apply_ids_filter(query, nil, true), do: from(s in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(s in query, where: false)
  # If ids param present with values, filter to those IDs
  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(s in query, where: s.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(s in query, where: false),
      else: from(s in query, where: s.id in ^parsed)
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
    order = if String.downcase(params["order"] || "") == "asc", do: :asc, else: :desc

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
    |> ImageLoader.load_image_url("Site")
  end

  def get_site(id) do
    Site
    |> preload([:faction, :juncture, attunements: [:character]])
    |> Repo.get(id)
    |> ImageLoader.load_image_url("Site")
  end

  def create_site(attrs \\ %{}) do
    %Site{}
    |> Site.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, site} ->
        site = Repo.preload(site, [:faction, :juncture])
        broadcast_change(site, :insert)
        # Track onboarding milestone
        ShotElixir.Models.Concerns.OnboardingTrackable.track_milestone(site)
        {:ok, site}

      error ->
        error
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

      error ->
        error
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

      error ->
        error
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
      nil ->
        :ok

      site ->
        site
        |> Repo.preload([:faction, :juncture], force: true)
        |> broadcast_change(:update)
    end
  end

  @doc """
  Duplicates a site, creating a new site with the same attributes.
  Also copies all attunements (character associations) to the new site.
  The new site has a unique name within the campaign.
  """
  def duplicate_site(%Site{} = site) do
    # Generate unique name for the duplicate
    unique_name = generate_unique_name(site.name, site.campaign_id)

    attrs =
      Map.from_struct(site)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:image_url)
      |> Map.delete(:image_positions)
      |> Map.delete(:campaign)
      |> Map.delete(:faction)
      |> Map.delete(:juncture)
      |> Map.delete(:attunements)
      |> Map.put(:name, unique_name)

    # Create the new site and copy attunements
    Repo.transaction(fn ->
      case create_site(attrs) do
        {:ok, new_site} ->
          # Queue image copy from original to new site
          queue_image_copy(site, new_site)

          # Copy all attunements from the original site
          attunements = list_site_attunements(site.id)

          Enum.each(attunements, fn attunement ->
            attunement_attrs = %{
              "site_id" => new_site.id,
              "character_id" => attunement.character_id
            }

            create_attunement(attunement_attrs)
          end)

          # Reload the new site with all preloads
          get_site!(new_site.id)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp queue_image_copy(source, target) do
    %{
      "source_type" => "Site",
      "source_id" => source.id,
      "target_type" => "Site",
      "target_id" => target.id
    }
    |> ImageCopyWorker.new()
    |> Oban.insert()
  end

  @doc """
  Generates a unique name for a site within a campaign.
  Strips any existing trailing number suffix like " (1)", " (2)", etc.
  Then finds the next available number if the base name exists.
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)

    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if the base name exists
    case Repo.exists?(
           from s in Site, where: s.campaign_id == ^campaign_id and s.name == ^base_name
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
           from s in Site, where: s.campaign_id == ^campaign_id and s.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end
end
