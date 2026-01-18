defmodule ShotElixir.Search do
  @moduledoc """
  Unified search across all entity types within a campaign.

  Provides campaign-scoped search functionality that queries multiple entity
  types in parallel and returns results grouped by type.
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

  # Maps entity type atoms to their schema modules
  @searchable_schemas %{
    characters: Character,
    vehicles: Vehicle,
    fights: Fight,
    sites: Site,
    parties: Party,
    factions: Faction,
    schticks: Schtick,
    weapons: Weapon,
    junctures: Juncture,
    adventures: Adventure
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
      |> Enum.map(fn {type, schema} ->
        Task.async(fn ->
          {type, search_schema(schema, campaign_id, search_term, limit)}
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

  defp search_schema(schema, campaign_id, search_term, limit) do
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
    |> ImageLoader.load_image_urls(record_type)
    |> Enum.map(&format_result(&1, schema))
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

  defp format_result(entity, schema) do
    %{
      id: entity.id,
      name: entity.name,
      image_url: entity.image_url,
      entity_class: schema_to_entity_class(schema),
      description: extract_description(entity)
    }
  end

  defp extract_description(%{description: desc}) when is_map(desc) do
    desc
    |> Map.get("description", "")
    |> to_string()
    |> strip_html_tags()
    |> String.slice(0, 100)
  end

  defp extract_description(%{description: desc}) when is_binary(desc) do
    desc
    |> strip_html_tags()
    |> String.slice(0, 100)
  end

  defp extract_description(_), do: nil

  # Strip HTML tags from a string
  defp strip_html_tags(nil), do: nil

  defp strip_html_tags(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
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
