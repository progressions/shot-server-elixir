defmodule ShotElixir.Factions do
  @moduledoc """
  The Factions context for managing campaign organizations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Factions.Faction
  alias ShotElixir.ImageLoader
  alias ShotElixir.Workers.ImageCopyWorker
  alias ShotElixir.Workers.SyncFactionToNotionWorker
  use ShotElixir.Models.Broadcastable

  def list_factions(campaign_id) do
    query =
      from f in Faction,
        where: f.campaign_id == ^campaign_id and f.active == true,
        order_by: [asc: fragment("lower(?)", f.name)],
        preload: [:image_positions]

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
      |> preload([:characters, :vehicles, :sites, :parties, :junctures, :image_positions])
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
    order = if String.downcase(params["order"] || "") == "asc", do: :asc, else: :desc

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
      |> broadcast_result(:insert, &Repo.preload(&1, [:image_positions]))

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
    result =
      faction
      |> Faction.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_faction} ->
        # Sync relationships if *_ids are provided
        if Map.has_key?(attrs, "character_ids") do
          sync_faction_characters(updated_faction, attrs["character_ids"])
        end

        if Map.has_key?(attrs, "vehicle_ids") do
          sync_faction_vehicles(updated_faction, attrs["vehicle_ids"])
        end

        if Map.has_key?(attrs, "site_ids") do
          sync_faction_sites(updated_faction, attrs["site_ids"])
        end

        if Map.has_key?(attrs, "party_ids") do
          sync_faction_parties(updated_faction, attrs["party_ids"])
        end

        if Map.has_key?(attrs, "juncture_ids") do
          sync_faction_junctures(updated_faction, attrs["juncture_ids"])
        end

        maybe_enqueue_notion_sync(updated_faction)

        updated_faction =
          Repo.preload(
            updated_faction,
            [:characters, :vehicles, :sites, :parties, :junctures, :image_positions], force: true)

        broadcast_change(updated_faction, :update)
        {:ok, updated_faction}

      error ->
        broadcast_result(result, :update)
        error
    end
  end

  # Sync functions for faction relationships
  defp sync_faction_characters(faction, character_ids) when is_list(character_ids) do
    alias ShotElixir.Characters.Character

    current_ids =
      from(c in Character, where: c.faction_id == ^faction.id, select: c.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    new_ids = Enum.map(character_ids, &to_string/1)
    to_add = new_ids -- current_ids
    to_remove = current_ids -- new_ids

    if Enum.any?(to_remove) do
      from(c in Character, where: c.id in ^to_remove)
      |> Repo.update_all(set: [faction_id: nil])
    end

    if Enum.any?(to_add) do
      from(c in Character, where: c.id in ^to_add)
      |> Repo.update_all(set: [faction_id: faction.id])
    end
  end

  defp sync_faction_characters(_, _), do: :ok

  defp sync_faction_vehicles(faction, vehicle_ids) when is_list(vehicle_ids) do
    alias ShotElixir.Vehicles.Vehicle

    current_ids =
      from(v in Vehicle, where: v.faction_id == ^faction.id, select: v.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    new_ids = Enum.map(vehicle_ids, &to_string/1)
    to_add = new_ids -- current_ids
    to_remove = current_ids -- new_ids

    if Enum.any?(to_remove) do
      from(v in Vehicle, where: v.id in ^to_remove)
      |> Repo.update_all(set: [faction_id: nil])
    end

    if Enum.any?(to_add) do
      from(v in Vehicle, where: v.id in ^to_add)
      |> Repo.update_all(set: [faction_id: faction.id])
    end
  end

  defp sync_faction_vehicles(_, _), do: :ok

  defp sync_faction_sites(faction, site_ids) when is_list(site_ids) do
    alias ShotElixir.Sites.Site

    current_ids =
      from(s in Site, where: s.faction_id == ^faction.id, select: s.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    new_ids = Enum.map(site_ids, &to_string/1)
    to_add = new_ids -- current_ids
    to_remove = current_ids -- new_ids

    if Enum.any?(to_remove) do
      from(s in Site, where: s.id in ^to_remove)
      |> Repo.update_all(set: [faction_id: nil])
    end

    if Enum.any?(to_add) do
      from(s in Site, where: s.id in ^to_add)
      |> Repo.update_all(set: [faction_id: faction.id])
    end
  end

  defp sync_faction_sites(_, _), do: :ok

  defp sync_faction_parties(faction, party_ids) when is_list(party_ids) do
    alias ShotElixir.Parties.Party

    current_ids =
      from(p in Party, where: p.faction_id == ^faction.id, select: p.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    new_ids = Enum.map(party_ids, &to_string/1)
    to_add = new_ids -- current_ids
    to_remove = current_ids -- new_ids

    if Enum.any?(to_remove) do
      from(p in Party, where: p.id in ^to_remove)
      |> Repo.update_all(set: [faction_id: nil])
    end

    if Enum.any?(to_add) do
      from(p in Party, where: p.id in ^to_add)
      |> Repo.update_all(set: [faction_id: faction.id])
    end
  end

  defp sync_faction_parties(_, _), do: :ok

  defp sync_faction_junctures(faction, juncture_ids) when is_list(juncture_ids) do
    alias ShotElixir.Junctures.Juncture

    current_ids =
      from(j in Juncture, where: j.faction_id == ^faction.id, select: j.id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    new_ids = Enum.map(juncture_ids, &to_string/1)
    to_add = new_ids -- current_ids
    to_remove = current_ids -- new_ids

    if Enum.any?(to_remove) do
      from(j in Juncture, where: j.id in ^to_remove)
      |> Repo.update_all(set: [faction_id: nil])
    end

    if Enum.any?(to_add) do
      from(j in Juncture, where: j.id in ^to_add)
      |> Repo.update_all(set: [faction_id: faction.id])
    end
  end

  defp sync_faction_junctures(_, _), do: :ok

  def delete_faction(%Faction{} = faction) do
    alias Ecto.Multi
    alias ShotElixir.Characters.Character
    alias ShotElixir.Vehicles.Vehicle
    alias ShotElixir.Sites.Site
    alias ShotElixir.Parties.Party
    alias ShotElixir.Junctures.Juncture
    alias ShotElixir.ImagePositions.ImagePosition
    alias ShotElixir.Media

    # Preload associations for broadcasting before deletion
    faction_with_associations =
      Repo.preload(faction, [:campaign, :image_positions])

    Multi.new()
    # Nullify faction_id on related entities instead of deleting them
    |> Multi.update_all(
      :nullify_characters,
      from(c in Character, where: c.faction_id == ^faction.id),
      set: [faction_id: nil]
    )
    |> Multi.update_all(
      :nullify_vehicles,
      from(v in Vehicle, where: v.faction_id == ^faction.id),
      set: [faction_id: nil]
    )
    |> Multi.update_all(
      :nullify_sites,
      from(s in Site, where: s.faction_id == ^faction.id),
      set: [faction_id: nil]
    )
    |> Multi.update_all(
      :nullify_parties,
      from(p in Party, where: p.faction_id == ^faction.id),
      set: [faction_id: nil]
    )
    |> Multi.update_all(
      :nullify_junctures,
      from(j in Juncture, where: j.faction_id == ^faction.id),
      set: [faction_id: nil]
    )
    |> Multi.delete_all(
      :delete_image_positions,
      from(ip in ImagePosition,
        where: ip.positionable_id == ^faction.id and ip.positionable_type == "Faction"
      )
    )
    # Orphan associated images instead of deleting them
    |> Multi.update_all(
      :orphan_images,
      Media.orphan_images_query("Faction", faction.id),
      []
    )
    |> Multi.delete(:faction, faction)
    |> Multi.run(:broadcast, fn _repo, %{faction: deleted_faction} ->
      broadcast_change(faction_with_associations, :delete)
      {:ok, deleted_faction}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{faction: faction}} -> {:ok, faction}
      {:error, :faction, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Duplicates a faction, creating a new faction with the same attributes.
  The new faction has a unique name within the campaign.
  """
  def duplicate_faction(%Faction{} = faction) do
    # Generate unique name for the duplicate
    unique_name = generate_unique_name(faction.name, faction.campaign_id)

    attrs =
      Map.from_struct(faction)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:image_url)
      |> Map.delete(:image_positions)
      |> Map.delete(:campaign)
      |> Map.delete(:characters)
      |> Map.delete(:vehicles)
      |> Map.delete(:sites)
      |> Map.delete(:parties)
      |> Map.delete(:junctures)
      |> Map.put(:name, unique_name)

    case create_faction(attrs) do
      {:ok, new_faction} ->
        queue_image_copy(faction, new_faction)
        {:ok, new_faction}

      error ->
        error
    end
  end

  defp queue_image_copy(source, target) do
    %{
      "source_type" => "Faction",
      "source_id" => source.id,
      "target_type" => "Faction",
      "target_id" => target.id
    }
    |> ImageCopyWorker.new()
    |> Oban.insert()
  end

  @doc """
  Generates a unique name for a faction within a campaign.
  Strips any existing trailing number suffix like " (1)", " (2)", etc.
  Then finds the next available number if the base name exists.
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)

    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if the base name exists
    case Repo.exists?(
           from f in Faction, where: f.campaign_id == ^campaign_id and f.name == ^base_name
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
           from f in Faction, where: f.campaign_id == ^campaign_id and f.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end

  defp maybe_enqueue_notion_sync(%Faction{notion_page_id: nil}), do: :ok

  defp maybe_enqueue_notion_sync(%Faction{id: id, notion_page_id: _page_id}) do
    %{faction_id: id}
    |> SyncFactionToNotionWorker.new()
    |> Oban.insert()

    :ok
  end
end
