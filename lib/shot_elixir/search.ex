defmodule ShotElixir.Search do
  @moduledoc """
  Unified search across all entity types within a campaign.

  Provides campaign-scoped search functionality that queries multiple entity
  types in parallel and returns results grouped by type.

  Returns full entity data compatible with existing badge components on the frontend.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.ImageLoader

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

  @default_limit_per_type 5
  @search_timeout_ms 5000

  # Maps entity type atoms to their schema modules and preloads
  @searchable_schemas %{
    characters: {Character, [:faction]},
    vehicles: {Vehicle, [:faction]},
    fights: {Fight, [shots: [:character, :vehicle]]},
    sites: {Site, [:faction, attunements: [:character]]},
    parties: {Party, [:faction, memberships: [:character, :vehicle]]},
    factions: {Faction, [:characters]},
    schticks: {Schtick, []},
    weapons: {Weapon, []},
    junctures: {Juncture, [:faction]},
    adventures: {Adventure, []}
  }

  @doc """
  Search across all entity types within a campaign.

  Returns a result map with:
  - `results`: Map of entity type atoms to lists of matching results
  - `meta`: Metadata including query, limit per type, and result counts

  ## Options
  - `:limit` - Maximum results per entity type (default: #{@default_limit_per_type})

  ## Examples

      iex> Search.search_campaign(campaign_id, "dragon")
      %{
        results: %{
          characters: [%{id: "...", name: "Dragon Lord", ...}],
          sites: [%{id: "...", name: "Dragon Palace", ...}]
        },
        meta: %{query: "dragon", limit_per_type: 5, total_count: 2}
      }
  """
  def search_campaign(campaign_id, query, opts \\ [])

  def search_campaign(campaign_id, query, opts) when is_binary(query) and byte_size(query) > 0 do
    limit = Keyword.get(opts, :limit, @default_limit_per_type)
    search_term = "%#{query}%"

    results =
      @searchable_schemas
      |> Enum.map(fn {type, {schema, preloads}} ->
        Task.async(fn ->
          {type, search_schema(schema, campaign_id, search_term, limit, preloads)}
        end)
      end)
      |> Task.await_many(@search_timeout_ms)
      |> Enum.filter(fn {_type, results} -> length(results) > 0 end)
      |> Map.new()

    total_count =
      results
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sum()

    %{
      results: results,
      meta: %{
        query: query,
        limit_per_type: limit,
        total_count: total_count
      }
    }
  end

  def search_campaign(_campaign_id, _query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit_per_type)

    %{
      results: %{},
      meta: %{
        query: "",
        limit_per_type: limit,
        total_count: 0
      }
    }
  end

  # Private helpers

  defp search_schema(schema, campaign_id, search_term, limit, preloads) do
    base_query =
      from(e in schema,
        where: e.campaign_id == ^campaign_id,
        order_by: [asc: fragment("LOWER(?)", e.name)],
        limit: ^limit
      )

    record_type = schema_to_entity_class(schema)

    base_query
    |> build_search_conditions(schema, search_term)
    |> Repo.all()
    |> Repo.preload(preloads)
    |> ImageLoader.load_image_urls(record_type)
  end

  defp build_search_conditions(query, schema, search_term) do
    fields = schema.__schema__(:fields)

    cond do
      # Characters and Vehicles have JSONB description field
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
