defmodule ShotElixir.Backlinks do
  @moduledoc """
  Query helpers for fetching backlinks ("mentioned in") relationships
  across Chi War entities. Backlinks are derived from each entity's
  `mentions` JSONB column, which stores resolved entity IDs keyed by
  entity type (e.g., %{"character" => ["uuid1", ...]}).

  This module intentionally keeps the query logic centralized so both
  controllers and future services can reuse the same semantics.
  """

  import Ecto.Query

  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Adventures.Adventure

  @max_limit 50

  @doc """
  Return up to `limit` entities that reference the target entity via the
  `mentions` field. Results are ordered by `updated_at` descending across
  all entity types.

  Filters:
  * `campaign_id` scope (required)
  * Active flag when available (entities with `active` boolean)
  """
  @spec list_backlinks(String.t(), String.t(), String.t(), non_neg_integer()) :: [map()]
  def list_backlinks(campaign_id, target_type, target_id, limit \\ 12)
      when is_binary(campaign_id) and is_binary(target_type) and is_binary(target_id) do
    limit = Enum.min([limit, @max_limit])

    query =
      Character
      |> backlinks_query("Character", campaign_id, target_type, target_id)
      |> union_all(^backlinks_query(Site, "Site", campaign_id, target_type, target_id))
      |> union_all(^backlinks_query(Party, "Party", campaign_id, target_type, target_id))
      |> union_all(^backlinks_query(Faction, "Faction", campaign_id, target_type, target_id))
      |> union_all(^backlinks_query(Juncture, "Juncture", campaign_id, target_type, target_id))
      |> union_all(^backlinks_query(Adventure, "Adventure", campaign_id, target_type, target_id))

    from(e in subquery(query), order_by: [desc: e.updated_at], limit: ^limit)
    |> Repo.all()
  end

  defp backlinks_query(schema, entity_class, campaign_id, target_type, target_id) do
    active_filter =
      if :active in schema.__schema__(:fields) do
        dynamic([e], e.active == true)
      else
        true
      end

    from e in schema,
      where: e.campaign_id == ^campaign_id,
      where: ^active_filter,
      # jsonb array containment-style lookup that can use a GIN index on mentions
      where:
        fragment(
          "? \\? ?",
          fragment("COALESCE(? -> ?, '[]'::jsonb)", e.mentions, ^target_type),
          ^target_id
        ),
      select: %{
        id: e.id,
        name: e.name,
        entity_class: ^entity_class,
        updated_at: e.updated_at
      }
  end
end
