defmodule ShotElixir.Parties do
  @moduledoc """
  The Parties context for managing groups of characters and vehicles.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Parties.{Party, Membership}

  def list_parties(campaign_id) do
    query = from p in Party,
      where: p.campaign_id == ^campaign_id and p.active == true,
      order_by: [asc: fragment("lower(?)", p.name)],
      preload: [:faction, :juncture, memberships: [:character, :vehicle]]

    Repo.all(query)
  end

  def get_party!(id) do
    Party
    |> preload([:faction, :juncture, memberships: [:character, :vehicle]])
    |> Repo.get!(id)
  end

  def get_party(id) do
    Party
    |> preload([:faction, :juncture, memberships: [:character, :vehicle]])
    |> Repo.get(id)
  end

  def create_party(attrs \\ %{}) do
    %Party{}
    |> Party.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, party} -> {:ok, Repo.preload(party, [:faction, :juncture, memberships: [:character, :vehicle]])}
      error -> error
    end
  end

  def update_party(%Party{} = party, attrs) do
    party
    |> Party.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, party} -> {:ok, Repo.preload(party, [:faction, :juncture, memberships: [:character, :vehicle]], force: true)}
      error -> error
    end
  end

  def delete_party(%Party{} = party) do
    party
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def add_member(party_id, member_attrs) do
    attrs = Map.put(member_attrs, "party_id", party_id)

    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, membership} -> {:ok, Repo.preload(membership, [:party, :character, :vehicle])}
      error -> error
    end
  end

  def remove_member(membership_id) do
    membership = Repo.get(Membership, membership_id)

    if membership do
      Repo.delete(membership)
    else
      {:error, :not_found}
    end
  end

  def get_membership_by_party_and_member(party_id, character_id, vehicle_id) do
    query = from m in Membership,
      where: m.party_id == ^party_id

    query = if character_id do
      where(query, [m], m.character_id == ^character_id)
    else
      where(query, [m], m.vehicle_id == ^vehicle_id)
    end

    Repo.one(query)
  end

  def list_party_memberships(party_id) do
    query = from m in Membership,
      where: m.party_id == ^party_id,
      preload: [:character, :vehicle]

    Repo.all(query)
  end
end