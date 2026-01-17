defmodule ShotElixir.Parties do
  @moduledoc """
  The Parties context for managing groups of characters and vehicles.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Parties.{Party, Membership, PartyTemplate}
  alias ShotElixir.ImageLoader
  alias ShotElixir.Slug
  alias ShotElixir.Workers.ImageCopyWorker
  alias ShotElixir.Workers.SyncPartyToNotionWorker
  use ShotElixir.Models.Broadcastable

  def list_parties(campaign_id) do
    query =
      from p in Party,
        where: p.campaign_id == ^campaign_id and p.active == true,
        order_by: [asc: fragment("lower(?)", p.name)],
        preload: [:faction, :juncture, :image_positions, memberships: [:character, :vehicle]]

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

    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))

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
    query = apply_at_a_glance_filter(query, params)

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
    count_query = apply_at_a_glance_filter(count_query, params)

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
      |> preload([:image_positions, memberships: [:character, :vehicle]])
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

  # If ids param not present at all, don't filter
  defp apply_ids_filter(query, _ids, false), do: query
  # If ids param present but nil or empty list, return no results
  defp apply_ids_filter(query, nil, true), do: from(p in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(p in query, where: false)
  # If ids param present with values, filter to those IDs
  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(p in query, where: p.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(p in query, where: false),
      else: from(p in query, where: p.id in ^parsed)
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

  defp apply_at_a_glance_filter(query, params) do
    case at_a_glance_param(params) do
      "true" ->
        from p in query, where: p.at_a_glance == true

      true ->
        from p in query, where: p.at_a_glance == true

      _ ->
        query
    end
  end

  defp at_a_glance_param(params) do
    Map.get(params, "at_a_glance")
  end

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if String.downcase(params["order"] || "") == "asc", do: :asc, else: :desc

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
    id = Slug.extract_uuid(id)
    Party
    |> preload([:faction, :juncture, :image_positions, memberships: [:character, :vehicle]])
    |> Repo.get!(id)
    |> ImageLoader.load_image_url("Party")
  end

  def get_party(id) do
    id = Slug.extract_uuid(id)
    Party
    |> preload([:faction, :juncture, :image_positions, memberships: [:character, :vehicle]])
    |> Repo.get(id)
    |> ImageLoader.load_image_url("Party")
  end

  def create_party(attrs \\ %{}) do
    %Party{}
    |> Party.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, party} ->
        party =
          Repo.preload(party, [
            :faction,
            :juncture,
            :image_positions,
            memberships: [:character, :vehicle]
          ])

        broadcast_change(party, :insert)
        # Track onboarding milestone
        ShotElixir.Models.Concerns.OnboardingTrackable.track_milestone(party)
        {:ok, party}

      error ->
        error
    end
  end

  def update_party(party, attrs, opts \\ [])

  def update_party(%Party{} = party, attrs, opts) do
    skip_notion_sync = Keyword.get(opts, :skip_notion_sync, false)

    party
    |> Party.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, party} ->
        # Sync character memberships if character_ids is provided
        party =
          if Map.has_key?(attrs, "character_ids") do
            sync_character_memberships(party, attrs["character_ids"])
          else
            party
          end

        # Sync vehicle memberships if vehicle_ids is provided
        party =
          if Map.has_key?(attrs, "vehicle_ids") do
            sync_vehicle_memberships(party, attrs["vehicle_ids"])
          else
            party
          end

        party =
          Repo.preload(
            party,
            [:faction, :juncture, :image_positions, memberships: [:character, :vehicle]],
            force: true
          )

        broadcast_change(party, :update)

        # Skip Notion sync when updating from webhook to prevent ping-pong loops
        unless skip_notion_sync do
          maybe_enqueue_notion_sync(party)
        end

        {:ok, party}

      error ->
        error
    end
  end

  # Syncs party character memberships to match the provided character_ids list.
  # Removes memberships for characters not in the list (both regular and slot-based).
  # Does not add new memberships - those should be added via add_member.
  defp sync_character_memberships(party, character_ids) when is_list(character_ids) do
    # Get current character memberships (all memberships with a character_id)
    current_memberships =
      from(m in Membership,
        where: m.party_id == ^party.id and not is_nil(m.character_id)
      )
      |> Repo.all()

    # Find memberships to remove (characters not in the new list)
    memberships_to_remove =
      Enum.filter(current_memberships, fn m ->
        m.character_id not in character_ids
      end)

    # Delete memberships for removed characters
    Enum.each(memberships_to_remove, fn membership ->
      Repo.delete(membership)
    end)

    party
  end

  defp sync_character_memberships(party, _), do: party

  # Syncs party vehicle memberships to match the provided vehicle_ids list.
  # Removes memberships for vehicles not in the list (both regular and slot-based).
  defp sync_vehicle_memberships(party, vehicle_ids) when is_list(vehicle_ids) do
    # Get current vehicle memberships (all memberships with a vehicle_id)
    current_memberships =
      from(m in Membership,
        where: m.party_id == ^party.id and not is_nil(m.vehicle_id)
      )
      |> Repo.all()

    # Find memberships to remove (vehicles not in the new list)
    memberships_to_remove =
      Enum.filter(current_memberships, fn m ->
        m.vehicle_id not in vehicle_ids
      end)

    # Delete memberships for removed vehicles
    Enum.each(memberships_to_remove, fn membership ->
      Repo.delete(membership)
    end)

    party
  end

  defp sync_vehicle_memberships(party, _), do: party

  def delete_party(%Party{} = party) do
    alias Ecto.Multi
    alias ShotElixir.ImagePositions.ImagePosition
    alias ShotElixir.Media

    # Preload associations for broadcasting before deletion
    party_with_associations =
      Repo.preload(party, [:faction, :juncture, :image_positions])

    Multi.new()
    # Delete related records first (memberships include slots)
    |> Multi.delete_all(
      :delete_memberships,
      from(m in Membership, where: m.party_id == ^party.id)
    )
    |> Multi.delete_all(
      :delete_image_positions,
      from(ip in ImagePosition,
        where: ip.positionable_id == ^party.id and ip.positionable_type == "Party"
      )
    )
    # Orphan associated images instead of deleting them
    |> Multi.update_all(
      :orphan_images,
      Media.orphan_images_query("Party", party.id),
      []
    )
    |> Multi.delete(:party, party)
    |> Multi.run(:broadcast, fn _repo, %{party: deleted_party} ->
      broadcast_change(party_with_associations, :delete)
      {:ok, deleted_party}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{party: party}} -> {:ok, party}
      {:error, :party, changeset, _} -> {:error, changeset}
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

  @doc """
  Duplicates a party, creating a new party with the same attributes.
  Also copies all memberships (characters and vehicles) to the new party.
  The new party has a unique name within the campaign.
  """
  def duplicate_party(%Party{} = party) do
    # Generate unique name for the duplicate
    unique_name = generate_unique_name(party.name, party.campaign_id)

    attrs =
      Map.from_struct(party)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:image_url)
      |> Map.delete(:image_positions)
      |> Map.delete(:campaign)
      |> Map.delete(:faction)
      |> Map.delete(:juncture)
      |> Map.delete(:memberships)
      |> Map.put(:name, unique_name)

    # Create the new party and copy memberships
    Repo.transaction(fn ->
      case create_party(attrs) do
        {:ok, new_party} ->
          # Queue image copy from original to new party
          queue_image_copy(party, new_party)

          # Copy all memberships from the original party
          memberships = list_party_memberships(party.id)

          Enum.each(memberships, fn membership ->
            member_attrs = %{
              "character_id" => membership.character_id,
              "vehicle_id" => membership.vehicle_id
            }

            add_member(new_party.id, member_attrs)
          end)

          # Reload the new party with all preloads
          get_party!(new_party.id)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp queue_image_copy(source, target) do
    %{
      "source_type" => "Party",
      "source_id" => source.id,
      "target_type" => "Party",
      "target_id" => target.id
    }
    |> ImageCopyWorker.new()
    |> Oban.insert()
  end

  @doc """
  Generates a unique name for a party within a campaign.
  Strips any existing trailing number suffix like " (1)", " (2)", etc.
  Then finds the next available number if the base name exists.
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)

    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if the base name exists
    case Repo.exists?(
           from p in Party, where: p.campaign_id == ^campaign_id and p.name == ^base_name
         ) do
      false ->
        base_name

      true ->
        # Find the next available number
        find_next_available_name(base_name, campaign_id, 1)
    end
  end

  def generate_unique_name(name, _campaign_id), do: name

  defp find_next_available_name(base_name, campaign_id, counter) do
    new_name = "#{base_name} (#{counter})"

    case Repo.exists?(
           from p in Party, where: p.campaign_id == ^campaign_id and p.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end

  # =============================================================================
  # Party Composition / Slot Management
  # =============================================================================

  @doc """
  Lists all available party templates.
  """
  def list_templates do
    PartyTemplate.list_templates()
  end

  @doc """
  Gets a specific template by key.
  """
  def get_template(key) do
    PartyTemplate.get_template(key)
  end

  @doc """
  Applies a template to a party, creating slots based on the template structure.
  Clears any existing slots before applying the new template.
  """
  def apply_template(party_id, template_key) do
    with {:ok, template} <- PartyTemplate.get_template(template_key),
         party when not is_nil(party) <- Repo.get(Party, party_id) do
      Repo.transaction(fn ->
        # Clear existing slots (memberships with roles)
        clear_all_slots(party_id)

        # Create new slots from template
        template.slots
        |> Enum.with_index()
        |> Enum.each(fn {slot_def, index} ->
          attrs = %{
            "party_id" => party_id,
            "role" => slot_def.role,
            "default_mook_count" => Map.get(slot_def, :default_mook_count),
            "position" => index
          }

          case create_slot(attrs) do
            {:ok, _slot} -> :ok
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

        # Return the updated party with slots
        get_party!(party_id)
      end)
    else
      {:error, :not_found} -> {:error, :template_not_found}
      nil -> {:error, :party_not_found}
    end
  end

  @doc """
  Adds a composition slot to a party.
  """
  def add_slot(party_id, attrs) do
    # Get the next position
    next_position = get_next_slot_position(party_id)

    slot_attrs =
      attrs
      |> Map.put("party_id", party_id)
      |> Map.put_new("position", next_position)

    create_slot(slot_attrs)
  end

  defp create_slot(attrs) do
    %Membership{}
    |> Membership.slot_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, slot} ->
        broadcast_party_update(slot.party_id)
        {:ok, Repo.preload(slot, [:party, :character, :vehicle])}

      error ->
        error
    end
  end

  @doc """
  Updates a slot (change role, mook count, populate with character, etc.)
  Requires party_id to verify the slot belongs to the specified party.
  """
  def update_slot(party_id, slot_id, attrs) do
    # Query for slot that belongs to the specified party
    case Repo.get_by(Membership, id: slot_id, party_id: party_id) do
      nil ->
        {:error, :not_found}

      slot ->
        slot
        |> Membership.update_slot_changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated_slot} ->
            broadcast_party_update(updated_slot.party_id)
            {:ok, Repo.preload(updated_slot, [:party, :character, :vehicle], force: true)}

          error ->
            error
        end
    end
  end

  @doc """
  Removes a slot from a party.
  Requires party_id to verify the slot belongs to the specified party.
  """
  def remove_slot(party_id, slot_id) do
    # Query for slot that belongs to the specified party
    case Repo.get_by(Membership, id: slot_id, party_id: party_id) do
      nil ->
        {:error, :not_found}

      slot ->
        case Repo.delete(slot) do
          {:ok, deleted_slot} ->
            # Reindex remaining slots
            reindex_slots(deleted_slot.party_id)
            broadcast_party_update(deleted_slot.party_id)
            {:ok, deleted_slot}

          error ->
            error
        end
    end
  end

  @doc """
  Populates a slot with a character.
  Requires party_id to verify the slot belongs to the specified party.
  """
  def populate_slot(party_id, slot_id, character_id) do
    update_slot(party_id, slot_id, %{"character_id" => character_id, "vehicle_id" => nil})
  end

  @doc """
  Populates a slot with a vehicle.
  Requires party_id to verify the slot belongs to the specified party.
  """
  def populate_slot_with_vehicle(party_id, slot_id, vehicle_id) do
    update_slot(party_id, slot_id, %{"vehicle_id" => vehicle_id, "character_id" => nil})
  end

  @doc """
  Clears a slot (removes character/vehicle but keeps the slot).
  Requires party_id to verify the slot belongs to the specified party.
  """
  def clear_slot(party_id, slot_id) do
    update_slot(party_id, slot_id, %{"character_id" => nil, "vehicle_id" => nil})
  end

  @doc """
  Reorders slots within a party.
  Expects a list of slot IDs in the desired order.
  """
  def reorder_slots(party_id, slot_ids) when is_list(slot_ids) do
    Repo.transaction(fn ->
      slot_ids
      |> Enum.with_index()
      |> Enum.each(fn {slot_id, index} ->
        from(m in Membership,
          where: m.id == ^slot_id and m.party_id == ^party_id
        )
        |> Repo.update_all(set: [position: index])
      end)

      broadcast_party_update(party_id)
      get_party!(party_id)
    end)
  end

  @doc """
  Lists all slots for a party, ordered by position.
  """
  def list_slots(party_id) do
    from(m in Membership,
      where: m.party_id == ^party_id and not is_nil(m.role),
      order_by: [asc: m.position, asc: m.id],
      preload: [:character, :vehicle]
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific slot by ID.
  """
  def get_slot(slot_id) do
    Membership
    |> preload([:party, :character, :vehicle])
    |> Repo.get(slot_id)
  end

  @doc """
  Gets a specific slot by ID, raises if not found.
  """
  def get_slot!(slot_id) do
    Membership
    |> preload([:party, :character, :vehicle])
    |> Repo.get!(slot_id)
  end

  @doc """
  Checks if a party has any composition slots.
  """
  def has_composition?(party_id) do
    from(m in Membership,
      where: m.party_id == ^party_id and not is_nil(m.role)
    )
    |> Repo.exists?()
  end

  # Private helper to clear all slots from a party
  defp clear_all_slots(party_id) do
    from(m in Membership,
      where: m.party_id == ^party_id and not is_nil(m.role)
    )
    |> Repo.delete_all()
  end

  # Get the next available position for a new slot
  defp get_next_slot_position(party_id) do
    max_position =
      from(m in Membership,
        where: m.party_id == ^party_id and not is_nil(m.role),
        select: max(m.position)
      )
      |> Repo.one()

    (max_position || -1) + 1
  end

  # Reindex slots after removal to maintain sequential positions
  defp reindex_slots(party_id) do
    slots =
      from(m in Membership,
        where: m.party_id == ^party_id and not is_nil(m.role),
        order_by: [asc: m.position, asc: m.id]
      )
      |> Repo.all()

    slots
    |> Enum.with_index()
    |> Enum.each(fn {slot, index} ->
      from(m in Membership, where: m.id == ^slot.id)
      |> Repo.update_all(set: [position: index])
    end)
  end

  defp maybe_enqueue_notion_sync(%Party{notion_page_id: nil}), do: :ok

  defp maybe_enqueue_notion_sync(%Party{id: id, notion_page_id: _page_id}) do
    %{party_id: id}
    |> SyncPartyToNotionWorker.new()
    |> Oban.insert()

    :ok
  end
end
