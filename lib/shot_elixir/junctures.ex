defmodule ShotElixir.Junctures do
  @moduledoc """
  The Junctures context for managing time periods in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Junctures.Juncture

  def list_junctures(campaign_id) do
    query = from j in Juncture,
      where: j.campaign_id == ^campaign_id and j.active == true,
      order_by: [asc: fragment("lower(?)", j.name)],
      preload: [:faction]

    Repo.all(query)
  end

  def get_juncture!(id) do
    Juncture
    |> preload(:faction)
    |> Repo.get!(id)
  end

  def get_juncture(id) do
    Juncture
    |> preload(:faction)
    |> Repo.get(id)
  end

  def create_juncture(attrs \\ %{}) do
    %Juncture{}
    |> Juncture.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, juncture} -> {:ok, Repo.preload(juncture, :faction)}
      error -> error
    end
  end

  def update_juncture(%Juncture{} = juncture, attrs) do
    juncture
    |> Juncture.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, juncture} -> {:ok, Repo.preload(juncture, :faction)}
      error -> error
    end
  end

  def delete_juncture(%Juncture{} = juncture) do
    juncture
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end
end