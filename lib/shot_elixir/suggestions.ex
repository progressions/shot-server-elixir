defmodule ShotElixir.Suggestions do
  @moduledoc """
  Context module for searching across multiple entity types for @ mentions.
  """

  import Ecto.Query
  alias ShotElixir.Repo

  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Schticks.Schtick
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.Junctures.Juncture

  @searchable_models [
    {Character, "Character", true},
    {Vehicle, "Vehicle", true},
    {Site, "Site", true},
    {Party, "Party", true},
    {Faction, "Faction", false},
    {Schtick, "Schtick", false},
    {Weapon, "Weapon", false},
    {Juncture, "Juncture", false}
  ]

  @doc """
  Search across all entity types for mentions matching the query.
  Returns results grouped by entity type.
  """
  def search(campaign_id, query) when is_binary(query) do
    query = query |> String.trim() |> String.downcase()

    if query == "" do
      empty_results()
    else
      search_term = "%#{query}%"

      @searchable_models
      |> Enum.map(fn {schema, class_name, has_active_filter} ->
        results =
          build_query(schema, campaign_id, search_term, has_active_filter)
          |> Repo.all()
          |> Enum.map(&format_result(&1, class_name))

        {class_name, results}
      end)
      |> Enum.into(%{})
      |> Map.put("meta", %{})
    end
  end

  defp build_query(schema, campaign_id, search_term, true) do
    from r in schema,
      where: r.campaign_id == ^campaign_id,
      where: r.active == true,
      where: ilike(r.name, ^search_term),
      select: %{id: r.id, name: r.name},
      order_by: [asc: fragment("lower(?)", r.name)],
      limit: 10
  end

  defp build_query(schema, campaign_id, search_term, false) do
    from r in schema,
      where: r.campaign_id == ^campaign_id,
      where: ilike(r.name, ^search_term),
      select: %{id: r.id, name: r.name},
      order_by: [asc: fragment("lower(?)", r.name)],
      limit: 10
  end

  defp format_result(%{id: id, name: name}, class_name) do
    %{id: id, label: name, className: class_name}
  end

  defp empty_results do
    %{
      "Character" => [],
      "Vehicle" => [],
      "Party" => [],
      "Site" => [],
      "Faction" => [],
      "Schtick" => [],
      "Weapon" => [],
      "Juncture" => [],
      "meta" => %{}
    }
  end
end
