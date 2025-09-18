defmodule ShotElixir.Fights do
  @moduledoc """
  The Fights context for managing combat encounters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Fights.{Fight, Shot}

  def list_fights(campaign_id) do
    query = from f in Fight,
      where: f.campaign_id == ^campaign_id and f.active == true,
      order_by: [desc: f.updated_at]

    Repo.all(query)
  end

  def list_campaign_fights(campaign_id, params \\ %{}, _current_user \\ nil) do
    # Get pagination parameters - handle both string and integer params
    per_page = case params["per_page"] do
      nil -> 15
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end

    page = case params["page"] do
      nil -> 1
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end

    offset = (page - 1) * per_page

    # Base query with visibility filtering
    query = from f in Fight,
      where: f.campaign_id == ^campaign_id and f.active == true

    # Apply basic filters
    query = if params["id"] do
      from f in query, where: f.id == ^params["id"]
    else
      query
    end

    query = if params["ids"] do
      ids = parse_ids(params["ids"])
      from f in query, where: f.id in ^ids
    else
      query
    end

    query = if params["search"] do
      from f in query, where: ilike(f.name, ^"%#{params["search"]}%")
    else
      query
    end

    # Status filtering
    query = if params["status"] do
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
    query = if params["season"] do
      if params["season"] == "__NONE__" do
        from f in query, where: is_nil(f.season)
      else
        from f in query, where: f.season == ^params["season"]
      end
    else
      query
    end

    # Session filtering
    query = if params["session"] do
      if params["session"] == "__NONE__" do
        from f in query, where: is_nil(f.session)
      else
        from f in query, where: f.session == ^params["session"]
      end
    else
      query
    end

    # Character filtering
    query = if params["character_id"] do
      from f in query,
        join: s in "shots", on: s.fight_id == f.id,
        where: s.character_id == ^params["character_id"]
    else
      query
    end

    # Vehicle filtering
    query = if params["vehicle_id"] do
      from f in query,
        join: s in "shots", on: s.fight_id == f.id,
        where: s.vehicle_id == ^params["vehicle_id"]
    else
      query
    end

    # User filtering (characters owned by user)
    query = if params["user_id"] do
      from f in query,
        join: s in "shots", on: s.fight_id == f.id,
        join: c in "characters", on: s.character_id == c.id,
        where: c.user_id == ^params["user_id"]
    else
      query
    end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination
    total_count = Repo.aggregate(query, :count, :id)

    # Get seasons for filtering UI
    seasons = query
    |> select([f], f.season)
    |> distinct(true)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()

    # Apply pagination
    fights = query
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
  end
  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

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
        order_by(query, [f], [desc: f.created_at, asc: f.id])
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
  end

  def update_fight(%Fight{} = fight, attrs) do
    fight
    |> Fight.changeset(attrs)
    |> Repo.update()
  end

  def delete_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def end_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(active: false, ended_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def touch_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(updated_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  # Shot management
  def create_shot(attrs \\ %{}) do
    %Shot{}
    |> Shot.changeset(attrs)
    |> Repo.insert()
  end

  def update_shot(%Shot{} = shot, attrs) do
    shot
    |> Shot.changeset(attrs)
    |> Repo.update()
  end

  def delete_shot(%Shot{} = shot) do
    Repo.delete(shot)
  end

  def act_on_shot(%Shot{} = shot) do
    shot
    |> Ecto.Changeset.change(acted: true)
    |> Repo.update()
  end

  def get_shot(id), do: Repo.get(Shot, id)

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
  end

  def remove_shot_drivers(shot_id) do
    from(sd in ShotElixir.Fights.ShotDriver, where: sd.shot_id == ^shot_id)
    |> Repo.delete_all()

    :ok
  end
end