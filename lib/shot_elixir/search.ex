defmodule ShotElixir.Search do
  @moduledoc """
  Unified search across all entity types within a campaign.
  """

  import Ecto.Query
  alias ShotElixir.Repo

  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Fights.Fight
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Schticks.Schtick
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Adventures.Adventure

  @limit_per_type 5

  @searchable_models %{
    "characters" => Character,
    "vehicles" => Vehicle,
    "fights" => Fight,
    "sites" => Site,
    "parties" => Party,
    "factions" => Faction,
    "schticks" => Schtick,
    "weapons" => Weapon,
    "junctures" => Juncture,
    "adventures" => Adventure
  }

  @doc """
  Search across all entity types for the given query within a campaign.

  Returns a map of entity type keys to lists of matching results.
  Each entity type is limited to #{@limit_per_type} results.
  """
  def search_all(campaign_id, query) when is_binary(query) and byte_size(query) > 0 do
    search_term = "%#{query}%"

    @searchable_models
    |> Enum.map(fn {key, schema} ->
      Task.async(fn ->
        results = search_schema(schema, campaign_id, search_term)
        {key, results}
      end)
    end)
    |> Task.await_many(5000)
    |> Enum.filter(fn {_key, results} -> length(results) > 0 end)
    |> Map.new()
  end

  def search_all(_campaign_id, _query), do: %{}

  defp search_schema(schema, campaign_id, search_term) do
    base_query =
      from(e in schema,
        where: e.campaign_id == ^campaign_id,
        order_by: [asc: fragment("LOWER(?)", e.name)],
        limit: @limit_per_type
      )

    # Build search conditions based on schema fields
    query = build_search_conditions(base_query, schema, search_term)

    query
    |> Repo.all()
    |> Enum.map(&format_result(&1, schema))
  end

  defp build_search_conditions(query, schema, search_term) do
    fields = schema.__schema__(:fields)

    cond do
      # Characters and Vehicles have jsonb description
      schema in [Character, Vehicle] ->
        from(e in query,
          where:
            ilike(e.name, ^search_term) or
              fragment("?->>'description' ILIKE ?", e.description, ^search_term)
        )

      # Schemas with both description and full_description text fields
      :description in fields and :full_description in fields ->
        from(e in query,
          where:
            ilike(e.name, ^search_term) or
              ilike(e.description, ^search_term) or
              ilike(e.full_description, ^search_term)
        )

      # Schemas with only description text field
      :description in fields ->
        from(e in query,
          where:
            ilike(e.name, ^search_term) or
              ilike(e.description, ^search_term)
        )

      # Schemas with only name field
      true ->
        from(e in query,
          where: ilike(e.name, ^search_term)
        )
    end
  end

  defp format_result(entity, schema) do
    %{
      id: entity.id,
      name: entity.name,
      image_url: get_image_url(entity),
      entity_class: schema_to_entity_class(schema),
      description: extract_description(entity)
    }
  end

  # Returns nil for image_url in search results.
  # Virtual image_url fields on schemas are not populated when querying
  # directly from the database, and calling ActiveStorage for each result
  # would add significant overhead to search.
  defp get_image_url(_entity), do: nil

  defp extract_description(%{description: desc}) when is_map(desc) do
    desc
    |> Map.get("description", "")
    |> to_string()
    |> String.slice(0, 100)
  end

  defp extract_description(%{description: desc}) when is_binary(desc) do
    String.slice(desc, 0, 100)
  end

  defp extract_description(_), do: nil

  defp schema_to_entity_class(Character), do: "Character"
  defp schema_to_entity_class(Vehicle), do: "Vehicle"
  defp schema_to_entity_class(Fight), do: "Fight"
  defp schema_to_entity_class(Site), do: "Site"
  defp schema_to_entity_class(Party), do: "Party"
  defp schema_to_entity_class(Faction), do: "Faction"
  defp schema_to_entity_class(Schtick), do: "Schtick"
  defp schema_to_entity_class(Weapon), do: "Weapon"
  defp schema_to_entity_class(Juncture), do: "Juncture"
  defp schema_to_entity_class(Adventure), do: "Adventure"
end
