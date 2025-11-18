defmodule ShotElixir.Parties do
  @moduledoc """
  The Parties context for managing groups of characters and vehicles.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Parties.{Party, Membership}
  alias ShotElixir.ImageLoader
  use ShotElixir.Models.Broadcastable

  def list_parties(campaign_id) do
    query =
      from p in Party,
        where: p.campaign_id == ^campaign_id and p.active == true,
        order_by: [asc: fragment("lower(?)", p.name)],
        preload: [:faction, :juncture, memberships: [:character, :vehicle]]

    query
    |> Repo.all()
    |> ImageLoader.load_image_urls("Party")
  end

  def list_campaign_parties(campaign_id, params \\ %{}, _current_user \\ nil) do
    # Get pagination parameters - handle both string and integer params
    per_page =
      case params["per_page"] do
        nil -> 15
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    page =
      case params["page"] do
        nil -> 1
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    offset = (page - 1) * per_page

    # Base query
    query =
      from p in Party,
        where: p.campaign_id == ^campaign_id

    # Apply basic filters
    query =
      if params["id"] do
        from p in query, where: p.id == ^params["id"]
      else
        query
      end

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from p in query, where: p.id in ^ids
      else
        query
      end

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from p in query, where: ilike(p.name, ^search_term)
      else
        query
      end

    # Faction filtering - handle "__NONE__" special case
    query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from p in query, where: is_nil(p.faction_id)
        else
          from p in query, where: p.faction_id == ^params["faction_id"]
        end
      else
        query
      end

    # Juncture filtering - handle "__NONE__" special case
    query =
      if params["juncture_id"] && params["juncture_id"] != "" do
        if params["juncture_id"] == "__NONE__" do
          from p in query, where: is_nil(p.juncture_id)
        else
          from p in query, where: p.juncture_id == ^params["juncture_id"]
        end
      else
        query
      end

    # Visibility filtering
    query = apply_visibility_filter(query, params)

    # Character filtering (parties with memberships to specific character)
    query =
      if params["character_id"] do
        from p in query,
          join: m in "memberships",
          on: m.party_id == p.id,
          where: m.character_id == ^params["character_id"]
      else
        query
      end

    # Vehicle filtering (parties with memberships to specific vehicle)
    query =
      if params["vehicle_id"] do
        from p in query,
          join: m in "memberships",
          on: m.party_id == p.id,
          where: m.vehicle_id == ^params["vehicle_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query = from p in Party, where: p.campaign_id == ^campaign_id

    # Apply same filters to count query
    count_query =
      if params["id"] do
        from p in count_query, where: p.id == ^params["id"]
      else
        count_query
      end

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from p in count_query, where: p.id in ^ids
      else
        count_query
      end

    count_query =
      if params["search"] do
        search_term = "%#{params["search"]}%"
        from p in count_query, where: ilike(p.name, ^search_term)
      else
        count_query
      end

    count_query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from p in count_query, where: is_nil(p.faction_id)
        else
          from p in count_query, where: p.faction_id == ^params["faction_id"]
        end
      else
        count_query
      end

    count_query =
      if params["juncture_id"] && params["juncture_id"] != "" do
        if params["juncture_id"] == "__NONE__" do
          from p in count_query, where: is_nil(p.juncture_id)
        else
          from p in count_query, where: p.juncture_id == ^params["juncture_id"]
        end
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)

    count_query =
      if params["character_id"] do
        from p in count_query,
          join: m in "memberships",
          on: m.party_id == p.id,
          where: m.character_id == ^params["character_id"]
      else
        count_query
      end

    count_query =
      if params["vehicle_id"] do
        from p in count_query,
          join: m in "memberships",
          on: m.party_id == p.id,
          where: m.vehicle_id == ^params["vehicle_id"]
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Get factions for filtering UI
    factions_query =
      from p in Party,
        where: p.campaign_id == ^campaign_id and p.active == true,
        join: f in "factions",
        on: p.faction_id == f.id,
        select: %{id: f.id, name: f.name},
        distinct: [f.id, f.name],
        order_by: [asc: fragment("LOWER(?)", f.name)]

    factions =
      factions_query
      |> Repo.all()
      |> Enum.map(fn entry ->
        Map.update(entry, :id, nil, fn id -> normalize_uuid(id) end)
      end)

    # Apply pagination
    parties =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> preload([memberships: [:character, :vehicle]])
      |> Repo.all()

    # Load image URLs for all parties efficiently
    parties_with_images = ImageLoader.load_image_urls(parties, "Party")

    # Return parties with pagination metadata and factions
    %{
      parties: parties_with_images,
      factions: factions,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      },
      is_autocomplete: params["autocomplete"] == "true" || params["autocomplete"] == true
    }
    |> ShotElixir.JsonSanitizer.sanitize()
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&normalize_uuid/1)
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: Enum.map(ids_param, &normalize_uuid/1)
  defp parse_ids(_), do: []

  defp apply_visibility_filter(query, params) do
    case params["visibility"] do
      "hidden" ->
        from p in query, where: p.active == false

      "all" ->
        query

      _ ->
        # Default to visible (active) only
        from p in query, where: p.active == true
    end
  end

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [p], [
          {^order, fragment("LOWER(?)", p.name)},
          {:asc, p.id}
        ])

      "created_at" ->
        order_by(query, [p], [{^order, p.created_at}, {:asc, p.id}])

      "updated_at" ->
        order_by(query, [p], [{^order, p.updated_at}, {:asc, p.id}])

      _ ->
        order_by(query, [p], desc: p.created_at, asc: p.id)
    end
  end

  def get_party!(id) do
    Party
    |> preload([:faction, :juncture, memberships: [:character, :vehicle]])
    |> Repo.get!(id)
    |> ImageLoader.load_image_url("Party")
  end

  def get_party(id) do
    Party
    |> preload([:faction, :juncture, memberships: [:character, :vehicle]])
    |> Repo.get(id)
    |> ImageLoader.load_image_url("Party")
  end

  def create_party(attrs \\ %{}) do
    %Party{}
    |> Party.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, party} ->
        party = Repo.preload(party, [:faction, :juncture, memberships: [:character, :vehicle]])
        broadcast_change(party, :insert)
        {:ok, party}

      error ->
        error
    end
  end

  def update_party(%Party{} = party, attrs) do
    party
    |> Party.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, party} ->
        party =
          Repo.preload(party, [:faction, :juncture, memberships: [:character, :vehicle]],
            force: true
          )

        broadcast_change(party, :update)
        {:ok, party}

      error ->
        error
    end
  end

  def delete_party(%Party{} = party) do
    party
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> case do
      {:ok, party} = result ->
        broadcast_change(party, :delete)
        result

      error ->
        error
    end
  end

  def add_member(party_id, member_attrs) do
    attrs = Map.put(member_attrs, "party_id", party_id)

    %Membership{}
    |> Membership.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, membership} ->
        broadcast_party_update(party_id)
        {:ok, Repo.preload(membership, [:party, :character, :vehicle])}

      error ->
        error
    end
  end

  def remove_member(membership_id) do
    membership = Repo.get(Membership, membership_id)

    if membership do
      membership
      |> Repo.delete()
      |> case do
        {:ok, membership} = result ->
          broadcast_party_update(membership.party_id)
          result

        error ->
          error
      end
    else
      {:error, :not_found}
    end
  end

  def get_membership_by_party_and_member(party_id, character_id, vehicle_id) do
    query =
      from m in Membership,
        where: m.party_id == ^party_id

    query =
      if character_id do
        where(query, [m], m.character_id == ^character_id)
      else
        where(query, [m], m.vehicle_id == ^vehicle_id)
      end

    Repo.one(query)
  end

  def list_party_memberships(party_id) do
    query =
      from m in Membership,
        where: m.party_id == ^party_id,
        preload: [:character, :vehicle]

    Repo.all(query)
  end

  defp normalize_uuid(nil), do: nil

  defp normalize_uuid(id) when is_binary(id) and byte_size(id) == 16 do
    case Ecto.UUID.load(id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_uuid(id), do: id

  defp broadcast_party_update(nil), do: :ok

  defp broadcast_party_update(party_id) do
    case get_party(party_id) do
      nil -> :ok
      party -> broadcast_change(party, :update)
    end
  end
end
