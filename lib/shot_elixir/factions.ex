defmodule ShotElixir.Factions do
  @moduledoc """
  The Factions context for managing campaign organizations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Factions.Faction

  def list_factions(campaign_id) do
    query = from f in Faction,
      where: f.campaign_id == ^campaign_id and f.active == true,
      order_by: [asc: fragment("lower(?)", f.name)]

    Repo.all(query)
  end

  def get_faction!(id), do: Repo.get!(Faction, id)
  def get_faction(id), do: Repo.get(Faction, id)

  def create_faction(attrs \\ %{}) do
    %Faction{}
    |> Faction.changeset(attrs)
    |> Repo.insert()
  end

  def update_faction(%Faction{} = faction, attrs) do
    faction
    |> Faction.changeset(attrs)
    |> Repo.update()
  end

  def delete_faction(%Faction{} = faction) do
    faction
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end
end