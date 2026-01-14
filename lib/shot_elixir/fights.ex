defmodule ShotElixir.Fights do
  @moduledoc """
  The Fights context for managing combat encounters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Fights.{Fight, Shot, FightEvent}
  alias ShotElixir.ImageLoader
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
      |> Repo.preload([:image_positions, shots: [:character, :vehicle]])

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
    Repo.get!(Fight, id)
    |> Repo.preload([:image_positions])
    |> ImageLoader.load_image_url("Fight")
  end

  def get_fight(id) do
    Repo.get(Fight, id)
    |> Repo.preload([:image_positions])
    |> ImageLoader.load_image_url("Fight")
  end

  def get_fight_with_shots(id) do
    Fight
    |> Repo.get(id)
    |> Repo.preload(shots: [:character, :vehicle, :character_effects])
    |> Repo.preload([:characters, :vehicles, :image_positions])
    |> ImageLoader.load_image_url("Fight")
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
    # Extract character_ids and vehicle_ids from attrs
    character_ids = attrs["character_ids"] || attrs[:character_ids]
    vehicle_ids = attrs["vehicle_ids"] || attrs[:vehicle_ids]

    # Remove them from attrs so they don't go through changeset
    attrs =
      attrs
      |> Map.delete("character_ids")
      |> Map.delete(:character_ids)
      |> Map.delete("vehicle_ids")
      |> Map.delete(:vehicle_ids)

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
  """
  def advance_shot_counter(%Fight{} = fight) do
    # Using sequence field as the shot counter
    new_counter = if fight.sequence > 0, do: fight.sequence - 1, else: 18
    update_fight(fight, %{sequence: new_counter})
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
      shots: [
        :character,
        :vehicle,
        :character_effects,
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
end
