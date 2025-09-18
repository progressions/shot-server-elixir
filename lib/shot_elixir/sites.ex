defmodule ShotElixir.Sites do
  @moduledoc """
  The Sites context for managing locations and attunements in campaigns.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Sites.{Site, Attunement}

  def list_sites(campaign_id) do
    query =
      from s in Site,
        where: s.campaign_id == ^campaign_id and s.active == true,
        order_by: [asc: fragment("lower(?)", s.name)],
        preload: [:faction, :juncture]

    Repo.all(query)
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
      {:ok, site} -> {:ok, Repo.preload(site, [:faction, :juncture])}
      error -> error
    end
  end

  def update_site(%Site{} = site, attrs) do
    site
    |> Site.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, site} -> {:ok, Repo.preload(site, [:faction, :juncture], force: true)}
      error -> error
    end
  end

  def delete_site(%Site{} = site) do
    site
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def create_attunement(attrs \\ %{}) do
    %Attunement{}
    |> Attunement.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, attunement} -> {:ok, Repo.preload(attunement, [:character, :site])}
      error -> error
    end
  end

  def delete_attunement(%Attunement{} = attunement) do
    Repo.delete(attunement)
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
end
