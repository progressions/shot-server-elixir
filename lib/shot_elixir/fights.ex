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