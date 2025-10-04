defmodule ShotElixir.Fights do
  @moduledoc """
  The Fights context for managing combat encounters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Fights.{Fight, Shot}
  use ShotElixir.Models.Broadcastable

  def list_fights(campaign_id) do
    query =
      from f in Fight,
        where: f.campaign_id == ^campaign_id and f.active == true,
        order_by: [desc: f.updated_at]

    Repo.all(query)
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

    # Normalize UUID parameters so string ids don't break binary comparisons
    params =
      params
      |> normalize_uuid_param("id")
      |> normalize_uuid_param("character_id")
      |> normalize_uuid_param("vehicle_id")
      |> normalize_uuid_param("user_id")

    # Base query with visibility filtering
    query =
      from f in Fight,
        where: f.campaign_id == ^campaign_id and f.active == true

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

        case Enum.reject(ids, &is_nil/1) do
          [] -> query
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
      if params["season"] do
        if params["season"] == "__NONE__" do
          from f in query, where: is_nil(f.season)
        else
          from f in query, where: f.season == ^params["season"]
        end
      else
        query
      end

    # Session filtering
    query =
      if params["session"] do
        if params["session"] == "__NONE__" do
          from f in query, where: is_nil(f.session)
        else
          from f in query, where: f.session == ^params["session"]
        end
      else
        query
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
        |> exclude(:order_by)  # Remove any ordering for the count
        |> select([f], f.id)
        |> Repo.all()
        |> length()
      else
        Repo.aggregate(query, :count, :id)
      end

    # Apply sorting AFTER getting the count
    query = apply_sorting(query, params)

    # Get seasons for filtering UI - separate query to avoid DISTINCT/ORDER BY issues
    seasons_query =
      from f in Fight,
        where: f.campaign_id == ^campaign_id and f.active == true,
        select: f.season,
        distinct: true

    seasons =
      seasons_query
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # Apply pagination
    fights =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Return fights with pagination metadata and seasons
    %{
      fights: fights,
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
    |> Enum.map(&normalize_uuid/1)
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: Enum.map(ids_param, &normalize_uuid/1)
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

      _ ->
        order_by(query, [f], desc: f.created_at, asc: f.id)
    end
  end

  def get_fight!(id), do: Repo.get!(Fight, id)
  def get_fight(id), do: Repo.get(Fight, id)

  def get_fight_with_shots(id) do
    Fight
    |> Repo.get(id)
    |> Repo.preload(shots: [:character, :vehicle])
  end

  def create_fight(attrs \\ %{}) do
    %Fight{}
    |> Fight.changeset(attrs)
    |> Repo.insert()
    |> broadcast_result(:insert, &Repo.preload(&1, fight_broadcast_preloads()))
  end

  def update_fight(%Fight{} = fight, attrs) do
    fight
    |> Fight.changeset(attrs)
    |> Repo.update()
    |> broadcast_result(:update, &Repo.preload(&1, fight_broadcast_preloads()))
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
    new_shot = max(shot.shot - shot_cost, 0)
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
      shots: [:character, :vehicle]
    ]
  end

  defp broadcast_fight_update(nil), do: :ok

  defp broadcast_fight_update(fight_id) do
    case get_fight(fight_id) do
      nil -> :ok
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
