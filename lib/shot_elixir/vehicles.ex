defmodule ShotElixir.Vehicles do
  @moduledoc """
  The Vehicles context for managing vehicles in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.ImageLoader
  alias ShotElixir.Workers.ImageCopyWorker
  use ShotElixir.Models.Broadcastable

  def list_vehicles(campaign_id) do
    query =
      from v in Vehicle,
        where: v.campaign_id == ^campaign_id and v.active == true,
        order_by: [asc: fragment("lower(?)", v.name)],
        preload: [:image_positions]

    Repo.all(query)
  end

  def list_campaign_vehicles(campaign_id, params \\ %{}, _current_user \\ nil) do
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

    # Base query with visibility filtering
    query =
      from v in Vehicle,
        where: v.campaign_id == ^campaign_id

    # Apply visibility filter (default to active only)
    query =
      if params["show_hidden"] == "true" do
        query
      else
        from v in query, where: v.active == true
      end

    query = apply_at_a_glance_filter(query, params)

    # Apply basic filters
    query =
      if params["id"] do
        from v in query, where: v.id == ^params["id"]
      else
        query
      end

    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))

    query =
      if params["search"] do
        from v in query, where: ilike(v.name, ^"%#{params["search"]}%")
      else
        query
      end

    # Faction filtering
    query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from v in query, where: is_nil(v.faction_id)
        else
          from v in query, where: v.faction_id == ^params["faction_id"]
        end
      else
        query
      end

    # Juncture filtering
    query =
      if params["juncture_id"] do
        if params["juncture_id"] == "__NONE__" do
          from v in query, where: is_nil(v.juncture_id)
        else
          from v in query, where: v.juncture_id == ^params["juncture_id"]
        end
      else
        query
      end

    # User filtering
    query =
      if params["user_id"] do
        from v in query, where: v.user_id == ^params["user_id"]
      else
        query
      end

    # Vehicle type filtering
    query =
      if params["vehicle_type"] && params["vehicle_type"] != "" do
        from v in query,
          where: fragment("?->>'Type' = ?", v.action_values, ^params["vehicle_type"])
      else
        query
      end

    # Archetype filtering
    query =
      if params["archetype"] && params["archetype"] != "" do
        if params["archetype"] == "__NONE__" do
          from v in query,
            where:
              fragment("?->>'Archetype' = ''", v.action_values) or
                fragment("?->>'Archetype' IS NULL", v.action_values)
        else
          from v in query,
            where: fragment("?->>'Archetype' = ?", v.action_values, ^params["archetype"])
        end
      else
        query
      end

    # Party filtering
    query =
      if params["party_id"] do
        from v in query,
          join: pm in "party_memberships",
          on: pm.vehicle_id == v.id,
          where: pm.party_id == ^params["party_id"]
      else
        query
      end

    # Fight filtering
    query =
      if params["fight_id"] do
        from v in query,
          join: s in "shots",
          on: s.vehicle_id == v.id,
          where: s.fight_id == ^params["fight_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query =
      from v in Vehicle,
        where: v.campaign_id == ^campaign_id

    # Apply same filters to count query
    count_query =
      if params["show_hidden"] == "true" do
        count_query
      else
        from v in count_query, where: v.active == true
      end

    count_query = apply_at_a_glance_filter(count_query, params)

    count_query =
      if params["id"] do
        from v in count_query, where: v.id == ^params["id"]
      else
        count_query
      end

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from v in count_query, where: v.id in ^ids
      else
        count_query
      end

    count_query =
      if params["search"] do
        from v in count_query, where: ilike(v.name, ^"%#{params["search"]}%")
      else
        count_query
      end

    count_query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from v in count_query, where: is_nil(v.faction_id)
        else
          from v in count_query, where: v.faction_id == ^params["faction_id"]
        end
      else
        count_query
      end

    count_query =
      if params["juncture_id"] do
        if params["juncture_id"] == "__NONE__" do
          from v in count_query, where: is_nil(v.juncture_id)
        else
          from v in count_query, where: v.juncture_id == ^params["juncture_id"]
        end
      else
        count_query
      end

    count_query =
      if params["user_id"] do
        from v in count_query, where: v.user_id == ^params["user_id"]
      else
        count_query
      end

    count_query =
      if params["vehicle_type"] && params["vehicle_type"] != "" do
        from v in count_query,
          where: fragment("?->>'Type' = ?", v.action_values, ^params["vehicle_type"])
      else
        count_query
      end

    count_query =
      if params["archetype"] && params["archetype"] != "" do
        if params["archetype"] == "__NONE__" do
          from v in count_query,
            where:
              fragment("?->>'Archetype' = ''", v.action_values) or
                fragment("?->>'Archetype' IS NULL", v.action_values)
        else
          from v in count_query,
            where: fragment("?->>'Archetype' = ?", v.action_values, ^params["archetype"])
        end
      else
        count_query
      end

    count_query =
      if params["party_id"] do
        from v in count_query,
          join: pm in "party_memberships",
          on: pm.vehicle_id == v.id,
          where: pm.party_id == ^params["party_id"]
      else
        count_query
      end

    count_query =
      if params["fight_id"] do
        from v in count_query,
          join: s in "shots",
          on: s.vehicle_id == v.id,
          where: s.fight_id == ^params["fight_id"]
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Get factions for filtering UI (respecting show_hidden parameter)
    show_hidden = params["show_hidden"] == "true"

    factions_query =
      from v in Vehicle,
        where: v.campaign_id == ^campaign_id and not is_nil(v.faction_id),
        join: f in "factions",
        on: f.id == v.faction_id,
        select: %{id: f.id, name: f.name, lower_name: fragment("LOWER(?)", f.name)},
        distinct: true,
        order_by: fragment("LOWER(?)", f.name)

    factions_query =
      if show_hidden do
        factions_query
      else
        from v in factions_query, where: v.active == true
      end

    factions =
      factions_query
      |> Repo.all()
      |> Enum.map(fn faction -> %{id: faction.id, name: faction.name} end)

    # Get archetypes and types (respecting show_hidden parameter)
    vehicles_for_meta_query =
      from v in Vehicle,
        where: v.campaign_id == ^campaign_id,
        select: v.action_values

    vehicles_for_meta_query =
      if show_hidden do
        vehicles_for_meta_query
      else
        from v in vehicles_for_meta_query, where: v.active == true
      end

    vehicles_for_meta = Repo.all(vehicles_for_meta_query)

    archetypes =
      vehicles_for_meta
      |> Enum.map(fn action_values -> Map.get(action_values || %{}, "Archetype") end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    types =
      vehicles_for_meta
      |> Enum.map(fn action_values -> Map.get(action_values || %{}, "Type") end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    # Apply pagination
    vehicles =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()
      |> Repo.preload([:image_positions])

    # Load image URLs for all vehicles efficiently
    vehicles_with_images = ImageLoader.load_image_urls(vehicles, "Vehicle")

    # Return vehicles with pagination metadata, factions, archetypes, and types
    %{
      vehicles: vehicles_with_images,
      factions: factions,
      archetypes: archetypes,
      types: types,
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
  defp apply_ids_filter(query, nil, true), do: from(v in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(v in query, where: false)
  # If ids param present with values, filter to those IDs
  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(v in query, where: v.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(v in query, where: false),
      else: from(v in query, where: v.id in ^parsed)
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
    order = if String.downcase(params["order"] || "") == "asc", do: :asc, else: :desc

    case sort do
      "type" ->
        order_by(query, [v], [
          {^order, fragment("COALESCE(?->>'Type', '')", v.action_values)},
          {:asc, v.id}
        ])

      "archetype" ->
        order_by(query, [v], [
          {^order, fragment("COALESCE(?->>'Archetype', '')", v.action_values)},
          {:asc, v.id}
        ])

      "name" ->
        order_by(query, [v], [
          {^order, fragment("LOWER(?)", v.name)},
          {:asc, v.id}
        ])

      "created_at" ->
        order_by(query, [v], [{^order, v.created_at}, {:asc, v.id}])

      "updated_at" ->
        order_by(query, [v], [{^order, v.updated_at}, {:asc, v.id}])

      _ ->
        order_by(query, [v], desc: v.created_at, asc: v.id)
    end
  end

  defp apply_at_a_glance_filter(query, params) do
    case at_a_glance_param(params) do
      "true" ->
        from v in query, where: v.at_a_glance == true

      true ->
        from v in query, where: v.at_a_glance == true

      _ ->
        query
    end
  end

  defp at_a_glance_param(params) do
    Map.get(params, "at_a_glance")
  end

  def get_vehicle!(id) do
    Repo.get!(Vehicle, id)
    |> Repo.preload([:image_positions])
    |> ImageLoader.load_image_url("Vehicle")
  end

  def get_vehicle(id) do
    Repo.get(Vehicle, id)
    |> Repo.preload([:image_positions])
    |> ImageLoader.load_image_url("Vehicle")
  end

  @doc """
  Gets multiple vehicles by their IDs in a single query.
  Returns a list of vehicles with image URLs loaded.
  """
  def list_vehicles_by_ids(ids) when is_list(ids) do
    ids = Enum.reject(ids, &is_nil/1)

    if ids == [] do
      []
    else
      from(v in Vehicle, where: v.id in ^ids)
      |> Repo.all()
      |> Repo.preload([:image_positions])
      |> ImageLoader.load_image_urls("Vehicle")
    end
  end

  def get_vehicle_with_preloads(id) do
    Vehicle
    |> Repo.get(id)
    |> Repo.preload([:user, :faction, :image_positions])
  end

  def create_vehicle(attrs \\ %{}) do
    %Vehicle{}
    |> Vehicle.changeset(attrs)
    |> Repo.insert()
    |> broadcast_result(:insert, &Repo.preload(&1, [:user, :faction, :image_positions]))
  end

  def update_vehicle(%Vehicle{} = vehicle, attrs) do
    vehicle
    |> Vehicle.changeset(attrs)
    |> Repo.update()
    |> broadcast_result(:update, &Repo.preload(&1, [:user, :faction, :image_positions]))
  end

  def delete_vehicle(%Vehicle{} = vehicle) do
    alias Ecto.Multi
    alias ShotElixir.Fights.Shot
    alias ShotElixir.Parties.Membership
    alias ShotElixir.ImagePositions.ImagePosition
    alias ShotElixir.Media

    # Preload associations for broadcasting before deletion
    vehicle_with_associations =
      Repo.preload(vehicle, [:user, :faction, :juncture, :image_positions])

    Multi.new()
    # Delete related records first
    |> Multi.delete_all(
      :delete_shots,
      from(s in Shot, where: s.vehicle_id == ^vehicle.id)
    )
    |> Multi.delete_all(
      :delete_memberships,
      from(m in Membership, where: m.vehicle_id == ^vehicle.id)
    )
    |> Multi.delete_all(
      :delete_image_positions,
      from(ip in ImagePosition,
        where: ip.positionable_id == ^vehicle.id and ip.positionable_type == "Vehicle"
      )
    )
    # Orphan associated images instead of deleting them
    |> Multi.update_all(
      :orphan_images,
      Media.orphan_images_query("Vehicle", vehicle.id),
      []
    )
    |> Multi.delete(:vehicle, vehicle)
    |> Multi.run(:broadcast, fn _repo, %{vehicle: deleted_vehicle} ->
      broadcast_change(vehicle_with_associations, :delete)
      {:ok, deleted_vehicle}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{vehicle: vehicle}} -> {:ok, vehicle}
      {:error, :vehicle, changeset, _} -> {:error, changeset}
    end
  end

  def update_chase_state(%Vehicle{} = vehicle, chase_params) do
    # Validate chase state parameters
    with :ok <- validate_chase_params(chase_params) do
      updated_values =
        Map.merge(vehicle.action_values || %{}, build_chase_state_updates(chase_params))

      vehicle
      |> Ecto.Changeset.change(action_values: updated_values)
      |> Repo.update()
      |> broadcast_result(:update, &Repo.preload(&1, [:user, :faction]))
    end
  end

  defp validate_chase_params(params) do
    errors = []

    errors =
      if params["position"] && params["position"] not in ["near", "far"] do
        ["Position must be 'near' or 'far'" | errors]
      else
        errors
      end

    errors =
      if params["chase_points"] && String.to_integer(params["chase_points"]) < 0 do
        ["Chase points cannot be negative" | errors]
      else
        errors
      end

    errors =
      if params["condition_points"] && String.to_integer(params["condition_points"]) < 0 do
        ["Condition points cannot be negative" | errors]
      else
        errors
      end

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp build_chase_state_updates(params) do
    updates = %{}

    updates =
      if params["chase_points"] do
        Map.put(updates, "Chase Points", String.to_integer(params["chase_points"]))
      else
        updates
      end

    updates =
      if params["condition_points"] do
        Map.put(updates, "Condition Points", String.to_integer(params["condition_points"]))
      else
        updates
      end

    updates =
      if params["position"] do
        Map.put(updates, "Position", params["position"])
      else
        updates
      end

    updates =
      if params["pursuer"] do
        Map.put(updates, "Pursuer", params["pursuer"])
      else
        updates
      end

    updates
  end

  def list_vehicle_archetypes do
    # Vehicle archetypes from Feng Shui 2 Action Guide
    # Keys are capitalized strings to match frontend VehicleArchetype type
    [
      # Small Vehicles
      %{
        "name" => "Horse",
        "Acceleration" => 6,
        "Handling" => 6,
        "Squeal" => 8,
        "Frame" => 0,
        "Crunch" => 0
      },
      %{
        "name" => "Motorcycle",
        "Acceleration" => 8,
        "Handling" => 8,
        "Squeal" => 10,
        "Frame" => 0,
        "Crunch" => 0
      },
      %{
        "name" => "Compact Car",
        "Acceleration" => 6,
        "Handling" => 7,
        "Squeal" => 9,
        "Frame" => 6,
        "Crunch" => 8
      },
      # Medium Vehicles
      %{
        "name" => "Cop Car",
        "Acceleration" => 8,
        "Handling" => 8,
        "Squeal" => 10,
        "Frame" => 6,
        "Crunch" => 8
      },
      %{
        "name" => "Junker Car",
        "Acceleration" => 5,
        "Handling" => 6,
        "Squeal" => 8,
        "Frame" => 6,
        "Crunch" => 8
      },
      %{
        "name" => "Muscle Car",
        "Acceleration" => 8,
        "Handling" => 8,
        "Squeal" => 10,
        "Frame" => 6,
        "Crunch" => 8
      },
      %{
        "name" => "Jeep, Military",
        "Acceleration" => 6,
        "Handling" => 6,
        "Squeal" => 7,
        "Frame" => 7,
        "Crunch" => 10
      },
      %{
        "name" => "Pickup Truck",
        "Acceleration" => 6,
        "Handling" => 6,
        "Squeal" => 8,
        "Frame" => 8,
        "Crunch" => 10
      },
      # Large Vehicles
      %{
        "name" => "Luxury Sedan",
        "Acceleration" => 8,
        "Handling" => 7,
        "Squeal" => 9,
        "Frame" => 7,
        "Crunch" => 9
      },
      %{
        "name" => "Panel Van",
        "Acceleration" => 6,
        "Handling" => 6,
        "Squeal" => 7,
        "Frame" => 8,
        "Crunch" => 9
      },
      %{
        "name" => "SUV, Security",
        "Acceleration" => 7,
        "Handling" => 6,
        "Squeal" => 8,
        "Frame" => 7,
        "Crunch" => 10
      },
      %{
        "name" => "Armored HUMV",
        "Acceleration" => 6,
        "Handling" => 6,
        "Squeal" => 7,
        "Frame" => 8,
        "Crunch" => 11
      },
      %{
        "name" => "18-Wheeler",
        "Acceleration" => 5,
        "Handling" => 5,
        "Squeal" => 7,
        "Frame" => 9,
        "Crunch" => 12
      },
      # Other Vehicles
      %{
        "name" => "Cigarette Boat",
        "Acceleration" => 9,
        "Handling" => 7,
        "Squeal" => 10,
        "Frame" => 2,
        "Crunch" => 4
      },
      %{
        "name" => "Coast Guard",
        "Acceleration" => 8,
        "Handling" => 7,
        "Squeal" => 9,
        "Frame" => 6,
        "Crunch" => 8
      },
      %{
        "name" => "Light Aircraft",
        "Acceleration" => 6,
        "Handling" => 6,
        "Squeal" => 8,
        "Frame" => 5,
        "Crunch" => 7
      },
      %{
        "name" => "Helicopter",
        "Acceleration" => 6,
        "Handling" => 7,
        "Squeal" => 8,
        "Frame" => 5,
        "Crunch" => 7
      },
      %{
        "name" => "Assault Copter",
        "Acceleration" => 10,
        "Handling" => 7,
        "Squeal" => 9,
        "Frame" => 6,
        "Crunch" => 8
      }
    ]
  end

  @doc """
  Duplicates a vehicle, creating a new vehicle with the same attributes.
  The new vehicle is assigned to the given user with a unique name.
  """
  def duplicate_vehicle(%Vehicle{} = vehicle, user) do
    # Generate unique name for the duplicate
    unique_name = generate_unique_name(vehicle.name, vehicle.campaign_id)

    attrs =
      Map.from_struct(vehicle)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:image_url)
      |> Map.delete(:image_positions)
      |> Map.delete(:user)
      |> Map.delete(:campaign)
      |> Map.delete(:faction)
      |> Map.delete(:juncture)
      |> Map.put(:name, unique_name)
      |> Map.put(:user_id, user.id)

    case create_vehicle(attrs) do
      {:ok, new_vehicle} ->
        # Queue image copy job
        queue_image_copy(vehicle, new_vehicle)
        {:ok, new_vehicle}

      error ->
        error
    end
  end

  defp queue_image_copy(source, target) do
    %{
      "source_type" => "Vehicle",
      "source_id" => source.id,
      "target_type" => "Vehicle",
      "target_id" => target.id
    }
    |> ImageCopyWorker.new()
    |> Oban.insert()
  end

  @doc """
  Generates a unique name for a vehicle within a campaign.
  Strips any existing trailing number suffix like " (1)", " (2)", etc.
  Then finds the next available number if the base name exists.
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)

    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if the base name exists
    case Repo.exists?(
           from v in Vehicle, where: v.campaign_id == ^campaign_id and v.name == ^base_name
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
           from v in Vehicle, where: v.campaign_id == ^campaign_id and v.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end
end
