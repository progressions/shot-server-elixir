defmodule ShotElixir.Fights do
  @moduledoc """
  The Fights context for managing combat encounters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Fights.{Fight, Shot, FightEvent}
  alias ShotElixir.Adventures.AdventureFight
  alias ShotElixir.ImageLoader
  alias ShotElixir.Slug
  alias ShotElixir.Effects
  use ShotElixir.Models.Broadcastable

  def list_fights(campaign_id) do
    query =
      from f in Fight,
        where: f.campaign_id == ^campaign_id and f.active == true,
        order_by: [desc: f.updated_at],
        preload: [:image_positions]

    query
    |> Repo.all()
    |> ImageLoader.load_image_urls("Fight")
  end

  def list_campaign_fights(campaign_id, params \\ %{}, _current_user \\ nil) do
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

    # Normalize UUID parameters for joins (character_id, vehicle_id, user_id)
    # Don't normalize "id" - Ecto handles string UUIDs in direct comparisons
    params =
      params
      |> normalize_uuid_param("character_id")
      |> normalize_uuid_param("vehicle_id")
      |> normalize_uuid_param("user_id")

    # Base query with campaign scope
    query = from f in Fight, where: f.campaign_id == ^campaign_id

    # Apply visibility filtering (default to active only)
    query = apply_visibility_filter(query, params)

    # Apply at_a_glance filter
    query = apply_at_a_glance_filter(query, params)

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

        # Rails behavior: empty ids param returns NO results (empty array)
        case Enum.reject(ids, &is_nil/1) do
          [] -> from f in query, where: false
          normalized_ids -> from f in query, where: f.id in ^normalized_ids
        end
      else
        query
      end

    query =
      if params["search"] do
        from f in query, where: ilike(f.name, ^"%#{params["search"]}%")
      else
        query
      end

    # Status filtering
    query =
      if params["status"] do
        case params["status"] do
          "Unstarted" -> from f in query, where: is_nil(f.started_at)
          "Started" -> from f in query, where: not is_nil(f.started_at) and is_nil(f.ended_at)
          "Ended" -> from f in query, where: not is_nil(f.started_at) and not is_nil(f.ended_at)
          _ -> query
        end
      else
        query
      end

    # Season filtering
    query =
      case blank_to_nil(params["season"]) do
        nil ->
          query

        "__NONE__" ->
          from f in query, where: is_nil(f.season)

        season ->
          from f in query, where: f.season == ^season
      end

    # Session filtering
    query =
      case blank_to_nil(params["session"]) do
        nil ->
          query

        "__NONE__" ->
          from f in query, where: is_nil(f.session)

        session ->
          from f in query, where: f.session == ^session
      end

    # Character filtering
    query =
      case params["character_id"] do
        nil ->
          query

        character_id ->
          from f in query,
            join: s in "shots",
            on: s.fight_id == f.id,
            where: s.character_id == ^character_id,
            distinct: true
      end

    # Vehicle filtering
    query =
      case params["vehicle_id"] do
        nil ->
          query

        vehicle_id ->
          from f in query,
            join: s in "shots",
            on: s.fight_id == f.id,
            where: s.vehicle_id == ^vehicle_id,
            distinct: true
      end

    # User filtering (characters owned by user)
    query =
      case params["user_id"] do
        nil ->
          query

        user_id ->
          from f in query,
            join: s in "shots",
            on: s.fight_id == f.id,
            join: c in "characters",
            on: s.character_id == c.id,
            where: c.user_id == ^user_id,
            distinct: true
      end

    # Get total count for pagination BEFORE applying sorting
    # This avoids the DISTINCT/ORDER BY conflict in PostgreSQL
    total_count =
      if params["character_id"] || params["vehicle_id"] || params["user_id"] do
        # For distinct queries with joins, we need a special count approach
        # The query already has distinct: true from the joins above
        query
        # Remove any ordering for the count
        |> exclude(:order_by)
        |> select([f], f.id)
        |> Repo.all()
        |> length()
      else
        Repo.aggregate(query, :count, :id)
      end

    # Apply sorting AFTER getting the count
    query = apply_sorting(query, params)

    # Apply pagination
    fights =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()
      |> Repo.preload([
        :image_positions,
        [shots: [:character, :vehicle]],
        [adventure_fights: :adventure]
      ])

    # Get seasons - only from actual results to match Rails behavior
    # When filter returns no results, seasons should be empty
    seasons =
      fights
      |> Enum.map(& &1.season)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    # Load image URLs for all fights efficiently
    fights_with_images = ImageLoader.load_image_urls(fights, "Fight")

    # Return fights with pagination metadata and seasons
    %{
      fights: fights_with_images,
      seasons: seasons,
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

    # Don't normalize - Ecto handles string UUIDs in IN queries
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp normalize_uuid_param(params, key) do
    case Map.fetch(params, key) do
      :error -> params
      {:ok, nil} -> params
      {:ok, value} -> Map.put(params, key, normalize_uuid(value))
    end
  end

  defp normalize_uuid(nil), do: nil
  defp normalize_uuid(value) when is_binary(value) and byte_size(value) == 16, do: value

  defp normalize_uuid(value) when is_binary(value) do
    case Ecto.UUID.dump(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_uuid(value), do: value

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

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

      "started_at" ->
        order_by(query, [f], [{^order, f.started_at}, {:asc, f.id}])

      "ended_at" ->
        order_by(query, [f], [{^order, f.ended_at}, {:asc, f.id}])

      "season" ->
        order_by(query, [f], [
          {^order, f.season},
          {^order, f.session},
          {:asc, fragment("LOWER(?)", f.name)}
        ])

      "session" ->
        order_by(query, [f], [
          {^order, f.session},
          {:asc, fragment("LOWER(?)", f.name)}
        ])

      "at_a_glance" ->
        order_by(query, [f], [
          {^order, f.at_a_glance},
          {:asc, fragment("LOWER(?)", f.name)}
        ])

      _ ->
        order_by(query, [f], desc: f.created_at, asc: f.id)
    end
  end

  defp apply_at_a_glance_filter(query, params) do
    case at_a_glance_param(params) do
      "true" ->
        from f in query, where: f.at_a_glance == true

      true ->
        from f in query, where: f.at_a_glance == true

      _ ->
        query
    end
  end

  defp at_a_glance_param(params) do
    Map.get(params, "at_a_glance")
  end

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

  def get_fight!(id) do
    id = Slug.extract_uuid(id)

    Repo.get!(Fight, id)
    |> Repo.preload([:image_positions, adventure_fights: [:adventure]])
    |> ImageLoader.load_image_url("Fight")
  end

  def get_fight(id) do
    id = Slug.extract_uuid(id)

    case Repo.get(Fight, id) do
      nil ->
        nil

      fight ->
        fight
        |> Repo.preload([:image_positions, adventure_fights: [:adventure]])
        |> ImageLoader.load_image_url("Fight")
    end
  end

  def get_fight_with_shots(id) do
    id = Slug.extract_uuid(id)

    case Repo.get(Fight, id) do
      nil ->
        nil

      fight ->
        fight
        |> Repo.preload(fight_broadcast_preloads())
        |> ImageLoader.load_image_url("Fight")
    end
  end

  def create_fight(attrs \\ %{}) do
    result =
      %Fight{}
      |> Fight.changeset(attrs)
      |> Repo.insert()
      |> broadcast_result(:insert, &Repo.preload(&1, fight_broadcast_preloads()))

    # Track onboarding milestone
    case result do
      {:ok, fight} ->
        ShotElixir.Models.Concerns.OnboardingTrackable.track_milestone(fight)
        {:ok, fight}

      error ->
        error
    end
  end

  def update_fight(%Fight{} = fight, attrs) do
    # Extract character_ids, vehicle_ids, and adventure_ids from attrs
    character_ids = attrs["character_ids"] || attrs[:character_ids]
    vehicle_ids = attrs["vehicle_ids"] || attrs[:vehicle_ids]
    adventure_ids = attrs["adventure_ids"] || attrs[:adventure_ids]

    # Remove them from attrs so they don't go through changeset
    attrs =
      attrs
      |> Map.delete("character_ids")
      |> Map.delete(:character_ids)
      |> Map.delete("vehicle_ids")
      |> Map.delete(:vehicle_ids)
      |> Map.delete("adventure_ids")
      |> Map.delete(:adventure_ids)

    # Start a transaction to update fight and manage shots
    Ecto.Multi.new()
    |> Ecto.Multi.update(:fight, Fight.changeset(fight, attrs))
    |> Ecto.Multi.run(:character_shots, fn _repo, %{fight: updated_fight} ->
      if character_ids do
        sync_character_shots(updated_fight, character_ids)
      else
        {:ok, []}
      end
    end)
    |> Ecto.Multi.run(:vehicle_shots, fn _repo, %{fight: updated_fight} ->
      if vehicle_ids do
        sync_vehicle_shots(updated_fight, vehicle_ids)
      else
        {:ok, []}
      end
    end)
    |> Ecto.Multi.run(:adventure_fights, fn _repo, %{fight: updated_fight} ->
      if adventure_ids do
        sync_adventure_fights(updated_fight, adventure_ids)
      else
        {:ok, []}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{fight: updated_fight}} ->
        result = Repo.preload(updated_fight, fight_broadcast_preloads(), force: true)
        broadcast_change(result, :update)
        {:ok, result}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp sync_adventure_fights(fight, adventure_ids) do
    # Get current adventure associations
    existing_links =
      Repo.all(from af in AdventureFight, where: af.fight_id == ^fight.id)

    existing_ids = Enum.map(existing_links, & &1.adventure_id)
    desired_ids = adventure_ids || []

    # Determine additions and removals
    to_add = desired_ids -- existing_ids
    to_remove = existing_ids -- desired_ids

    # Add new associations
    Enum.each(to_add, fn adventure_id ->
      %AdventureFight{}
      |> AdventureFight.changeset(%{fight_id: fight.id, adventure_id: adventure_id})
      |> Repo.insert!()
    end)

    # Remove old associations
    if to_remove != [] do
      from(af in AdventureFight,
        where: af.fight_id == ^fight.id and af.adventure_id in ^to_remove
      )
      |> Repo.delete_all()
    end

    {:ok, []}
  end

  defp sync_character_shots(fight, character_ids) do
    # Get current shots with character_ids in the fight
    existing_shots =
      Repo.all(from s in Shot, where: s.fight_id == ^fight.id and not is_nil(s.character_id))

    # Count existing shots per character_id
    existing_counts =
      existing_shots
      |> Enum.group_by(& &1.character_id)
      |> Enum.map(fn {char_id, shots} -> {char_id, length(shots)} end)
      |> Map.new()

    # Count desired shots per character_id (preserving duplicates)
    desired_counts =
      (character_ids || [])
      |> Enum.frequencies()

    # Get all unique character IDs from both existing and desired
    all_character_ids =
      MapSet.union(
        MapSet.new(Map.keys(existing_counts)),
        MapSet.new(Map.keys(desired_counts))
      )

    # For each character_id, add or remove shots to match desired count
    Enum.each(all_character_ids, fn char_id ->
      existing_count = Map.get(existing_counts, char_id, 0)
      desired_count = Map.get(desired_counts, char_id, 0)

      cond do
        desired_count > existing_count ->
          # Add more shots for this character
          shots_to_add = desired_count - existing_count

          Enum.each(1..shots_to_add, fn _ ->
            %Shot{}
            |> Shot.changeset(%{fight_id: fight.id, character_id: char_id, shot: nil})
            |> Repo.insert!()
          end)

        desired_count < existing_count ->
          # Remove excess shots for this character
          shots_to_remove_count = existing_count - desired_count

          # Get existing shot IDs for this character, sorted by creation date (remove newest first)
          shots_for_char =
            existing_shots
            |> Enum.filter(&(&1.character_id == char_id))
            |> Enum.sort_by(& &1.created_at, :desc)
            |> Enum.take(shots_to_remove_count)

          shot_ids_to_remove = Enum.map(shots_for_char, & &1.id)

          if shot_ids_to_remove != [] do
            # Clear driver_id on any shots referencing the shots to be removed
            from(s in Shot, where: s.driver_id in ^shot_ids_to_remove)
            |> Repo.update_all(set: [driver_id: nil])

            # Delete the shots
            from(s in Shot, where: s.id in ^shot_ids_to_remove)
            |> Repo.delete_all()
          end

        true ->
          # Count matches, nothing to do
          :ok
      end
    end)

    {:ok, []}
  end

  defp sync_vehicle_shots(fight, vehicle_ids) do
    # Get current shots with vehicle_ids in the fight
    existing_shots =
      Repo.all(from s in Shot, where: s.fight_id == ^fight.id and not is_nil(s.vehicle_id))

    # Count existing shots per vehicle_id
    existing_counts =
      existing_shots
      |> Enum.group_by(& &1.vehicle_id)
      |> Enum.map(fn {vehicle_id, shots} -> {vehicle_id, length(shots)} end)
      |> Map.new()

    # Count desired shots per vehicle_id (preserving duplicates)
    desired_counts =
      (vehicle_ids || [])
      |> Enum.frequencies()

    # Get all unique vehicle IDs from both existing and desired
    all_vehicle_ids =
      MapSet.union(
        MapSet.new(Map.keys(existing_counts)),
        MapSet.new(Map.keys(desired_counts))
      )

    # For each vehicle_id, add or remove shots to match desired count
    Enum.each(all_vehicle_ids, fn vehicle_id ->
      existing_count = Map.get(existing_counts, vehicle_id, 0)
      desired_count = Map.get(desired_counts, vehicle_id, 0)

      cond do
        desired_count > existing_count ->
          # Add more shots for this vehicle
          shots_to_add = desired_count - existing_count

          Enum.each(1..shots_to_add, fn _ ->
            %Shot{}
            |> Shot.changeset(%{fight_id: fight.id, vehicle_id: vehicle_id, shot: nil})
            |> Repo.insert!()
          end)

        desired_count < existing_count ->
          # Remove excess shots for this vehicle
          shots_to_remove_count = existing_count - desired_count

          # Get existing shot IDs for this vehicle, sorted by creation date (remove newest first)
          shots_for_vehicle =
            existing_shots
            |> Enum.filter(&(&1.vehicle_id == vehicle_id))
            |> Enum.sort_by(& &1.created_at, :desc)
            |> Enum.take(shots_to_remove_count)

          shot_ids_to_remove = Enum.map(shots_for_vehicle, & &1.id)

          if shot_ids_to_remove != [] do
            # Clear driving_id on any shots referencing the shots to be removed
            from(s in Shot, where: s.driving_id in ^shot_ids_to_remove)
            |> Repo.update_all(set: [driving_id: nil])

            # Delete the shots
            from(s in Shot, where: s.id in ^shot_ids_to_remove)
            |> Repo.delete_all()
          end

        true ->
          # Count matches, nothing to do
          :ok
      end
    end)

    {:ok, []}
  end

  @doc """
  Advance the shot counter for a fight.
  Also checks for and removes any expired character effects.
  """
  def advance_shot_counter(%Fight{} = fight) do
    # Using sequence field as the shot counter
    new_counter = if fight.sequence > 0, do: fight.sequence - 1, else: 18

    case update_fight(fight, %{sequence: new_counter}) do
      {:ok, updated_fight} ->
        # Check for expired effects after advancing the shot
        # Result is intentionally discarded - effect expiry is best-effort
        # and should not fail the shot advancement
        {:ok, _expired_effects} = Effects.expire_effects_for_fight(updated_fight)
        {:ok, updated_fight}

      error ->
        error
    end
  end

  @doc """
  Reset the shot counter to 18.
  """
  def reset_shot_counter(%Fight{} = fight) do
    # Using sequence field as the shot counter
    update_fight(fight, %{sequence: 18})
  end

  @doc """
  Reset a fight to its initial state.
  This resets the sequence to 0, clears started_at/ended_at,
  and resets all shots to their default state (no initiative, no impairments, etc).
  Optionally deletes all fight events.
  """
  def reset_fight(%Fight{} = fight, opts \\ []) do
    delete_events = Keyword.get(opts, :delete_events, false)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:fight, fn _ ->
      fight
      |> Ecto.Changeset.change(%{
        sequence: 0,
        started_at: nil,
        ended_at: nil,
        active: true
      })
    end)
    |> Ecto.Multi.run(:reset_shots, fn _repo, _changes ->
      # Reset all shots in this fight
      from(s in Shot, where: s.fight_id == ^fight.id)
      |> Repo.update_all(
        set: [
          shot: nil,
          impairments: 0,
          count: 0,
          was_rammed_or_damaged: false
        ]
      )

      {:ok, :shots_reset}
    end)
    |> Ecto.Multi.run(:delete_events, fn _repo, _changes ->
      if delete_events do
        from(fe in FightEvent, where: fe.fight_id == ^fight.id)
        |> Repo.delete_all()
      end

      {:ok, :events_handled}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{fight: updated_fight}} ->
        result = Repo.preload(updated_fight, fight_broadcast_preloads(), force: true)
        broadcast_change(result, :update)
        {:ok, result}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def delete_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete, &Repo.preload(&1, fight_broadcast_preloads()))
  end

  def end_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(
      active: false,
      ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
    |> broadcast_result(:update, &Repo.preload(&1, fight_broadcast_preloads()))
  end

  def touch_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(updated_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
    |> broadcast_result(:update, &Repo.preload(&1, fight_broadcast_preloads()))
  end

  def create_fight_event(attrs, opts \\ []) do
    %FightEvent{}
    |> FightEvent.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, fight_event} = result ->
        if Keyword.get(opts, :broadcast, true) do
          broadcast_fight_update(fight_event.fight_id)
        end

        result

      error ->
        error
    end
  end

  @doc """
  Lists all fight events for a given fight, ordered chronologically.
  """
  def list_fight_events(fight_id) do
    from(fe in FightEvent,
      where: fe.fight_id == ^fight_id,
      order_by: [asc: fe.created_at]
    )
    |> Repo.all()
  end

  # Shot management
  def create_shot(attrs \\ %{}) do
    %Shot{}
    |> Shot.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, shot} = result ->
        broadcast_fight_update(shot.fight_id)
        result

      error ->
        error
    end
  end

  def update_shot(%Shot{} = shot, attrs) do
    shot
    |> Shot.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, shot} = result ->
        broadcast_fight_update(shot.fight_id)
        result

      error ->
        error
    end
  end

  def delete_shot(%Shot{} = shot) do
    shot
    |> Repo.delete()
    |> case do
      {:ok, shot} = result ->
        broadcast_fight_update(shot.fight_id)
        result

      error ->
        error
    end
  end

  def act_on_shot(%Shot{} = shot) do
    shot
    |> Ecto.Changeset.change(acted: true)
    |> Repo.update()
    |> case do
      {:ok, shot} = result ->
        broadcast_fight_update(shot.fight_id)
        result

      error ->
        error
    end
  end

  def get_shot(id), do: Repo.get(Shot, id)

  @doc """
  Acts a shot, moving it down the initiative track.
  """
  def act_shot(%Shot{} = shot, shot_cost) do
    new_shot = shot.shot - shot_cost
    update_shot(shot, %{shot: new_shot, acted: true})
  end

  def get_shot_with_drivers(id) do
    Shot
    |> Repo.get(id)
    |> Repo.preload(:shot_drivers)
  end

  # Shot driver management
  def create_shot_driver(attrs \\ %{}) do
    %ShotElixir.Fights.ShotDriver{}
    |> ShotElixir.Fights.ShotDriver.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, shot_driver} = result ->
        shot_driver.shot_id
        |> fight_id_from_shot()
        |> broadcast_fight_update()

        result

      error ->
        error
    end
  end

  def remove_shot_drivers(shot_id) do
    fight_id = fight_id_from_shot(shot_id)

    from(sd in ShotElixir.Fights.ShotDriver, where: sd.shot_id == ^shot_id)
    |> Repo.delete_all()
    |> case do
      {count, _} ->
        if fight_id && count > 0, do: broadcast_fight_update(fight_id)
        {count, nil}

      other ->
        other
    end
  end

  # Driver assignment functions for Rails compatibility
  def clear_vehicle_drivers(fight_id, vehicle_shot_id) do
    from(s in Shot,
      where: s.fight_id == ^fight_id and s.driving_id == ^vehicle_shot_id,
      update: [set: [driving_id: nil]]
    )
    |> Repo.update_all([])
    |> case do
      {count, _} ->
        if count > 0, do: broadcast_fight_update(fight_id)
        {count, nil}

      other ->
        other
    end
  end

  def assign_driver(driver_shot, vehicle_shot_id) do
    driver_shot
    |> Ecto.Changeset.change(driving_id: vehicle_shot_id)
    |> Repo.update()
    |> case do
      {:ok, shot} = result ->
        broadcast_fight_update(shot.fight_id)
        result

      error ->
        error
    end
  end

  defp fight_broadcast_preloads do
    [
      :image_positions,
      :characters,
      :vehicles,
      :effects,
      [adventure_fights: [:adventure]],
      shots: [
        :character,
        :vehicle,
        :character_effects,
        :location_ref,
        character: [:faction, :character_schticks, :carries],
        vehicle: [:faction]
      ]
    ]
  end

  defp broadcast_fight_update(nil), do: :ok

  defp broadcast_fight_update(fight_id) do
    case get_fight(fight_id) do
      nil ->
        :ok

      fight ->
        fight
        |> Repo.preload(fight_broadcast_preloads())
        |> broadcast_change(:update)

        :ok
    end
  end

  defp fight_id_from_shot(nil), do: nil

  defp fight_id_from_shot(shot_id) do
    shot_id
    |> get_shot()
    |> case do
      nil -> nil
      shot -> shot.fight_id
    end
  end

  # =============================================================================
  # Location Functions
  # =============================================================================

  alias ShotElixir.Fights.Location
  alias ShotElixir.Fights.LocationConnection

  @doc """
  Lists all locations for a fight.
  """
  def list_fight_locations(fight_id) do
    from(l in Location, where: l.fight_id == ^fight_id, order_by: [asc: l.name])
    |> Repo.all()
    |> Repo.preload([:shots, :from_connections, :to_connections])
  end

  @doc """
  Lists all locations for a site (templates).
  """
  def list_site_locations(site_id) do
    from(l in Location, where: l.site_id == ^site_id, order_by: [asc: l.name])
    |> Repo.all()
    |> Repo.preload([:from_connections, :to_connections])
  end

  @doc """
  Gets a single location by ID.
  """
  def get_location(id) do
    Repo.get(Location, id)
    |> Repo.preload([:fight, :site, :shots, :from_connections, :to_connections])
  end

  @doc """
  Gets a location by ID, raises if not found.
  """
  def get_location!(id) do
    Repo.get!(Location, id)
    |> Repo.preload([:fight, :site, :shots, :from_connections, :to_connections])
  end

  # Location layout constants (matching frontend)
  @default_location_width 200
  @default_location_height 150
  @location_spacing 20
  @grid_columns 5
  @grid_rows 10

  @doc """
  Creates a location for a fight.

  Automatically calculates a non-overlapping position when neither `position_x` nor
  `position_y` is provided. If either coordinate is provided, both should be provided
  or the unprovided coordinate will default to 0.
  """
  def create_fight_location(fight_id, attrs) do
    attrs = Map.put(attrs, "fight_id", fight_id)

    # Calculate position if not explicitly provided (lightweight query for position only)
    attrs =
      maybe_calculate_position(attrs, fn ->
        list_locations_for_position_calc(:fight, fight_id)
      end)

    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a location for a site (template).

  Automatically calculates a non-overlapping position when neither `position_x` nor
  `position_y` is provided. If either coordinate is provided, both should be provided
  or the unprovided coordinate will default to 0.
  """
  def create_site_location(site_id, attrs) do
    attrs = Map.put(attrs, "site_id", site_id)

    # Calculate position if not explicitly provided (lightweight query for position only)
    attrs =
      maybe_calculate_position(attrs, fn ->
        list_locations_for_position_calc(:site, site_id)
      end)

    %Location{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  # Lightweight query for position calculation - only fetches position/size fields
  defp list_locations_for_position_calc(:fight, fight_id) do
    from(l in Location,
      where: l.fight_id == ^fight_id,
      select: %{
        position_x: l.position_x,
        position_y: l.position_y,
        width: l.width,
        height: l.height
      }
    )
    |> Repo.all()
  end

  defp list_locations_for_position_calc(:site, site_id) do
    from(l in Location,
      where: l.site_id == ^site_id,
      select: %{
        position_x: l.position_x,
        position_y: l.position_y,
        width: l.width,
        height: l.height
      }
    )
    |> Repo.all()
  end

  # Calculate position for a new location if not explicitly provided
  defp maybe_calculate_position(attrs, get_existing_locations_fn) do
    # Check if position was explicitly provided (handle both string and atom keys)
    has_position_x = Map.has_key?(attrs, "position_x") or Map.has_key?(attrs, :position_x)
    has_position_y = Map.has_key?(attrs, "position_y") or Map.has_key?(attrs, :position_y)

    # Only auto-calculate if NEITHER position coordinate was provided
    # This allows explicit (0, 0) placement when desired
    if has_position_x or has_position_y do
      attrs
    else
      existing_locations = get_existing_locations_fn.()
      {pos_x, pos_y} = calculate_non_overlapping_position(existing_locations)

      attrs
      |> Map.put("position_x", pos_x)
      |> Map.put("position_y", pos_y)
    end
  end

  @doc """
  Calculates a position for a new location that doesn't overlap with existing locations.
  Uses a grid-based approach, trying positions left-to-right, top-to-bottom.
  If the grid is full, places the location below the grid to avoid overlap.
  """
  def calculate_non_overlapping_position(existing_locations) do
    cell_width = @default_location_width + @location_spacing
    cell_height = @default_location_height + @location_spacing

    # Build all grid positions in row-major order
    grid_positions =
      for row <- 0..(@grid_rows - 1),
          col <- 0..(@grid_columns - 1) do
        {col * cell_width, row * cell_height}
      end

    # Find the first clear position within the grid
    case Enum.find(grid_positions, fn {x, y} ->
           position_is_clear?(x, y, existing_locations)
         end) do
      nil ->
        # If the grid is completely full, place the new location just below the grid
        {0, @grid_rows * cell_height}

      {x, y} ->
        {x, y}
    end
  end

  # Check if a position doesn't overlap with any existing locations
  defp position_is_clear?(x, y, existing_locations) do
    new_width = @default_location_width
    new_height = @default_location_height

    not Enum.any?(existing_locations, fn loc ->
      loc_width = loc.width || @default_location_width
      loc_height = loc.height || @default_location_height

      # Check for overlap (with spacing buffer)
      x < loc.position_x + loc_width + @location_spacing and
        x + new_width + @location_spacing > loc.position_x and
        y < loc.position_y + loc_height + @location_spacing and
        y + new_height + @location_spacing > loc.position_y
    end)
  end

  @doc """
  Updates a location.
  """
  def update_location(%Location{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a location. Shots with this location will have location_id set to nil.
  """
  def delete_location(%Location{} = location) do
    Repo.delete(location)
  end

  # =============================================================================
  # LocationConnection Functions
  # =============================================================================

  @doc """
  Lists all location connections for a fight.
  """
  def list_fight_location_connections(fight_id) do
    from(lc in LocationConnection,
      join: l in Location,
      on: lc.from_location_id == l.id,
      where: l.fight_id == ^fight_id,
      preload: [:from_location, :to_location]
    )
    |> Repo.all()
  end

  @doc """
  Lists all location connections for a site.
  """
  def list_site_location_connections(site_id) do
    from(lc in LocationConnection,
      join: l in Location,
      on: lc.from_location_id == l.id,
      where: l.site_id == ^site_id,
      preload: [:from_location, :to_location]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single location connection by ID.
  """
  def get_location_connection(id) do
    Repo.get(LocationConnection, id)
    |> Repo.preload([:from_location, :to_location])
  end

  @doc """
  Creates a location connection for a fight.
  Validates that both locations belong to the same fight.
  """
  def create_fight_location_connection(fight_id, attrs) do
    # First validate the locations belong to the fight
    from_id = attrs["from_location_id"] || attrs[:from_location_id]
    to_id = attrs["to_location_id"] || attrs[:to_location_id]

    with {:ok, _from_loc} <- validate_location_in_fight(from_id, fight_id),
         {:ok, _to_loc} <- validate_location_in_fight(to_id, fight_id) do
      changeset = LocationConnection.changeset(%LocationConnection{}, attrs)

      case LocationConnection.validate_same_scope(changeset) do
        {:ok, validated_changeset} ->
          validated_changeset
          |> Repo.insert()
          |> case do
            {:ok, connection} ->
              {:ok, Repo.preload(connection, [:from_location, :to_location])}

            error ->
              error
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a location connection for a site.
  Validates that both locations belong to the same site.
  """
  def create_site_location_connection(site_id, attrs) do
    from_id = attrs["from_location_id"] || attrs[:from_location_id]
    to_id = attrs["to_location_id"] || attrs[:to_location_id]

    with {:ok, _from_loc} <- validate_location_in_site(from_id, site_id),
         {:ok, _to_loc} <- validate_location_in_site(to_id, site_id) do
      changeset = LocationConnection.changeset(%LocationConnection{}, attrs)

      case LocationConnection.validate_same_scope(changeset) do
        {:ok, validated_changeset} ->
          validated_changeset
          |> Repo.insert()
          |> case do
            {:ok, connection} ->
              {:ok, Repo.preload(connection, [:from_location, :to_location])}

            error ->
              error
          end

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a location connection.
  """
  def update_location_connection(%LocationConnection{} = connection, attrs) do
    connection
    |> LocationConnection.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, [:from_location, :to_location])}
      error -> error
    end
  end

  @doc """
  Deletes a location connection.
  """
  def delete_location_connection(%LocationConnection{} = connection) do
    Repo.delete(connection)
  end

  defp validate_location_in_fight(location_id, fight_id) do
    case get_location(location_id) do
      nil ->
        {:error, "location not found"}

      location ->
        if location.fight_id == fight_id do
          {:ok, location}
        else
          {:error, "location does not belong to this fight"}
        end
    end
  end

  defp validate_location_in_site(location_id, site_id) do
    case get_location(location_id) do
      nil ->
        {:error, "location not found"}

      location ->
        if location.site_id == site_id do
          {:ok, location}
        else
          {:error, "location does not belong to this site"}
        end
    end
  end

  # =============================================================================
  # Quick-Set Location Functions
  # =============================================================================

  @doc """
  Sets the location for a shot, creating the location if it doesn't exist.
  Returns {:ok, shot, created} where created is true if a new location was created.
  """
  def set_shot_location(shot, nil), do: clear_shot_location(shot)
  def set_shot_location(shot, ""), do: clear_shot_location(shot)

  def set_shot_location(shot, name) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      clear_shot_location(shot)
    else
      Repo.transaction(fn ->
        {location, created} = find_or_create_fight_location(shot.fight_id, name)

        {:ok, updated_shot} =
          shot
          |> Shot.changeset(%{location_id: location.id})
          |> Repo.update()

        updated_shot = Repo.preload(updated_shot, [:location_ref, :character, :vehicle])
        {updated_shot, created}
      end)
      |> case do
        {:ok, {shot, created}} -> {:ok, shot, created}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Clears the location from a shot.
  """
  def clear_shot_location(shot) do
    {:ok, updated_shot} =
      shot
      |> Shot.changeset(%{location_id: nil})
      |> Repo.update()

    updated_shot = Repo.preload(updated_shot, [:location_ref, :character, :vehicle])
    {:ok, updated_shot, false}
  end

  @doc """
  Finds an existing location by name (case-insensitive) or creates a new one.
  Returns {location, created} where created is a boolean.
  """
  def find_or_create_fight_location(fight_id, name) do
    # Try to find existing location (case-insensitive)
    query =
      from l in Location,
        where: l.fight_id == ^fight_id and fragment("lower(?)", l.name) == ^String.downcase(name)

    case Repo.one(query) do
      nil ->
        # Create new location
        {:ok, location} = create_fight_location(fight_id, %{"name" => name})
        {location, true}

      location ->
        {location, false}
    end
  end
end
