defmodule ShotElixir.Characters do
  @moduledoc """
  The Characters context for managing Feng Shui 2 characters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias ShotElixir.Fights.Shot
  alias ShotElixir.Parties.Membership
  alias ShotElixir.Sites.Attunement
  alias ShotElixir.ImageLoader
  alias Ecto.Multi
  use ShotElixir.Models.Broadcastable

  # Character types are defined in the database enum

  def list_characters(campaign_id) do
    query =
      from c in Character,
        where: c.campaign_id == ^campaign_id and c.active == true

    Repo.all(query)
  end

  def list_campaign_characters(campaign_id, params \\ %{}, current_user \\ nil) do
    require Logger
    Logger.debug("Characters.list_campaign_characters called with params: #{inspect(params)}")

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

    # Base query filters by campaign_id
    query =
      from c in Character,
        where: c.campaign_id == ^campaign_id

    # Apply visibility filtering
    query = apply_visibility_filter(query, params)

    # Apply single id filter if present
    query =
      if params["id"] && params["id"] != "" do
        from c in query, where: c.id == ^params["id"]
      else
        query
      end

    # Apply ids filter if present (handles empty ids to return no results)
    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))

    # Apply user_id filter if present
    # Note: unassigned filter takes precedence over user_id filter to avoid
    # conflicting conditions (user_id = X AND user_id IS NULL would return zero results)
    query =
      cond do
        # If unassigned filter is set to true, filter for characters with no user_id
        # This takes precedence over any user_id filter
        params["unassigned"] == "true" || params["unassigned"] == true ->
          from c in query, where: is_nil(c.user_id)

        # Otherwise, apply user_id filter if present
        params["user_id"] && params["user_id"] != "" ->
          from c in query, where: c.user_id == ^params["user_id"]

        # No filter applied
        true ->
          query
      end

    # Apply juncture_id filter if present
    # Special case: "__NONE__" means juncture_id IS NULL
    query =
      if params["juncture_id"] && params["juncture_id"] != "" do
        if params["juncture_id"] == "__NONE__" do
          from c in query, where: is_nil(c.juncture_id)
        else
          from c in query, where: c.juncture_id == ^params["juncture_id"]
        end
      else
        query
      end

    # Apply party_id filter if present (joins memberships table)
    # A party can potentially have multiple copies of a character.
    query =
      if params["party_id"] && params["party_id"] != "" do
        from c in query,
          join: m in Membership,
          on: m.character_id == c.id,
          where: m.party_id == ^params["party_id"]
      else
        query
      end

    # Apply site_id filter if present (joins attunements table)
    # A site could potentially have multiple copies of a character.
    query =
      if params["site_id"] && params["site_id"] != "" do
        from c in query,
          join: a in Attunement,
          on: a.character_id == c.id,
          where: a.site_id == ^params["site_id"]
      else
        query
      end

    # Apply fight_id filter if present
    query =
      if params["fight_id"] do
        from c in query,
          join: s in Shot,
          on: s.character_id == c.id,
          where: s.fight_id == ^params["fight_id"]
      else
        query
      end

    # Apply character_type filter if present
    # character_type is stored in action_values["Type"]
    query =
      if params["character_type"] && params["character_type"] != "" do
        Logger.debug("Applying character_type filter: #{params["character_type"]}")

        from c in query,
          where: fragment("?->>'Type' = ?", c.action_values, ^params["character_type"])
      else
        Logger.debug("No character_type filter applied (empty or nil)")
        query
      end

    # Apply faction_id filter if present
    # Special case: "__NONE__" means faction_id IS NULL
    # Empty string is treated as no filter
    query =
      if params["faction_id"] && params["faction_id"] != "" do
        if params["faction_id"] == "__NONE__" do
          from c in query, where: is_nil(c.faction_id)
        else
          from c in query, where: c.faction_id == ^params["faction_id"]
        end
      else
        query
      end

    # Apply archetype filter if present
    # archetype is stored in action_values["Archetype"]
    # Special case: "__NONE__" means empty string archetype
    query =
      if params["archetype"] && params["archetype"] != "" do
        archetype_value = if params["archetype"] == "__NONE__", do: "", else: params["archetype"]

        from c in query,
          where: fragment("?->>'Archetype' = ?", c.action_values, ^archetype_value)
      else
        query
      end

    # Apply search filter if present
    query =
      if params["search"] && params["search"] != "" do
        search_term = "%#{params["search"]}%"
        from c in query, where: ilike(c.name, ^search_term)
      else
        query
      end

    # Apply template filtering - defaults to excluding templates
    # Skip template filter if specific IDs are requested
    query =
      if params["ids"] do
        query
      else
        apply_template_filter(query, params, current_user)
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination
    total_count =
      query
      |> exclude(:order_by)
      |> select([c], count(c.id))
      |> Repo.one()

    Logger.debug("Total count found: #{total_count}")

    # Apply pagination
    characters =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    Logger.debug("Characters returned after pagination: #{length(characters)}")

    # Load image URLs for all characters efficiently
    characters_with_images = ImageLoader.load_image_urls(characters, "Character")

    # Extract unique archetypes from characters
    archetypes =
      characters
      |> Enum.map(fn c -> get_in(c.action_values, ["Archetype"]) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    # Get factions used by these characters (like Rails does)
    faction_ids = Enum.map(characters, & &1.faction_id)
    factions = ShotElixir.Factions.get_factions_by_ids(faction_ids)

    # Return characters with pagination metadata, archetypes, and factions
    %{
      characters: characters_with_images,
      archetypes: archetypes,
      factions: factions,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      },
      is_autocomplete: params["autocomplete"] == "true" || params["autocomplete"] == true
    }
  end

  defp apply_template_filter(query, params, current_user) do
    # Template filtering - only admins and gamemasters can access templates
    # Regular players should never see templates
    is_admin = current_user && current_user.admin
    is_gamemaster = current_user && current_user.gamemaster
    can_access_templates = is_admin || is_gamemaster

    template_filter = params["template_filter"] || params["is_template"]

    if !can_access_templates do
      # Non-admin/non-gamemaster users always get non-templates only
      from c in query, where: c.is_template == false or is_nil(c.is_template)
    else
      # Admin users and gamemasters can use template filtering
      case template_filter do
        "templates" ->
          from c in query, where: c.is_template == true

        "all" ->
          # No filter on is_template, show all
          query

        "true" ->
          # Legacy parameter support
          from c in query, where: c.is_template == true

        "false" ->
          # Legacy parameter support
          from c in query, where: c.is_template == false or is_nil(c.is_template)

        "non-templates" ->
          # Explicit non-templates filter
          from c in query, where: c.is_template == false or is_nil(c.is_template)

        nil ->
          # Default to non-templates
          from c in query, where: c.is_template == false or is_nil(c.is_template)

        "" ->
          # Empty string defaults to non-templates
          from c in query, where: c.is_template == false or is_nil(c.is_template)

        _ ->
          # Invalid value defaults to non-templates
          from c in query, where: c.is_template == false or is_nil(c.is_template)
      end
    end
  end

  defp apply_visibility_filter(query, params) do
    case params["show_hidden"] do
      "true" ->
        # Show both active and inactive characters
        query

      "false" ->
        # Show only active characters
        from c in query, where: c.active == true

      _ ->
        # Default to showing only active characters
        from c in query, where: c.active == true
    end
  end

  # If ids param not present at all, don't filter
  defp apply_ids_filter(query, _ids, false), do: query
  # If ids param present but nil or empty list, return no results
  defp apply_ids_filter(query, nil, true), do: from(c in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(c in query, where: false)
  # If ids param present with values, filter to those IDs
  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(c in query, where: c.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(c in query, where: false),
      else: from(c in query, where: c.id in ^parsed)
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_sorting(query, params) do
    alias ShotElixir.Factions.Faction
    alias ShotElixir.Junctures.Juncture

    sort = params["sort"] || "created_at"
    order = if String.upcase(params["order"] || "") == "ASC", do: :asc, else: :desc

    case sort do
      "type" ->
        order_by(query, [c], [
          {^order, fragment("LOWER(COALESCE(?->>'Type', ''))", c.action_values)},
          {:asc, fragment("LOWER(?)", c.name)},
          {:asc, c.id}
        ])

      "archetype" ->
        order_by(query, [c], [
          {^order, fragment("LOWER(COALESCE(?->>'Archetype', ''))", c.action_values)},
          {:asc, fragment("LOWER(?)", c.name)},
          {:asc, c.id}
        ])

      "name" ->
        order_by(query, [c], [
          {^order, fragment("LOWER(?)", c.name)},
          {:asc, c.id}
        ])

      "faction" ->
        # Join with factions table to sort by faction name
        # Characters without factions will appear last in ASC, first in DESC
        null_sort = if order == :asc, do: "zzz", else: ""

        query
        |> join(:left, [c], f in Faction, on: c.faction_id == f.id, as: :faction)
        |> order_by([c, faction: f], [
          {^order, fragment("LOWER(COALESCE(?, ?))", f.name, ^null_sort)},
          {:asc, fragment("LOWER(?)", c.name)},
          {:asc, c.id}
        ])

      "juncture" ->
        # Join with junctures table to sort by juncture name
        # Characters without junctures will appear last in ASC, first in DESC
        null_sort = if order == :asc, do: "zzz", else: ""

        query
        |> join(:left, [c], j in Juncture, on: c.juncture_id == j.id, as: :juncture)
        |> order_by([c, juncture: j], [
          {^order, fragment("LOWER(COALESCE(?, ?))", j.name, ^null_sort)},
          {:asc, fragment("LOWER(?)", c.name)},
          {:asc, c.id}
        ])

      "created_at" ->
        order_by(query, [c], [{^order, c.created_at}, {:asc, c.id}])

      "updated_at" ->
        order_by(query, [c], [{^order, c.updated_at}, {:asc, c.id}])

      _ ->
        order_by(query, [c], desc: c.created_at, asc: c.id)
    end
  end

  def search_characters(campaign_id, search_term) do
    query =
      from c in Character,
        where: c.campaign_id == ^campaign_id and c.active == true,
        where: ilike(c.name, ^"%#{search_term}%"),
        limit: 10,
        order_by: [asc: c.name]

    Repo.all(query)
  end

  def get_character!(id) do
    Repo.get!(Character, id)
    |> Repo.preload([
      :image_positions,
      :weapons,
      :schticks,
      :parties,
      :sites,
      :faction,
      :juncture,
      :user
    ])
    |> ImageLoader.load_image_url("Character")
  end

  def get_character(id) do
    case Repo.get(Character, id) do
      nil ->
        nil

      character ->
        character
        |> Repo.preload([
          :image_positions,
          :weapons,
          :schticks,
          :parties,
          :sites,
          :faction,
          :juncture,
          :user
        ])
        |> ImageLoader.load_image_url("Character")
    end
  end

  @doc """
  Find or create a character by name and campaign_id.
  Used by Notion sync to ensure characters exist before updating from Notion.
  """
  def find_or_create_by_name_and_campaign(name, campaign_id) do
    case Repo.get_by(Character, name: name, campaign_id: campaign_id) do
      nil ->
        create_character(%{name: name, campaign_id: campaign_id})

      character ->
        {:ok, character}
    end
  end

  def create_character(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:character, Character.changeset(%Character{}, attrs))
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      # Preload associations before broadcasting
      character_with_associations =
        Repo.preload(character, [:user, :faction, :juncture, :image_positions])

      broadcast_change(character_with_associations, :insert)
      {:ok, character}
    end)
    |> Multi.run(:track_milestone, fn _repo, %{character: character} ->
      # Track onboarding milestone
      ShotElixir.Models.Concerns.OnboardingTrackable.track_milestone(character)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
    end
  end

  def update_character(%Character{} = character, attrs) do
    # Extract association IDs from attrs (they're not part of the schema)
    {weapon_ids, attrs} =
      Map.pop(attrs, "weapon_ids", Map.pop(attrs, :weapon_ids, nil) |> elem(0))

    {schtick_ids, attrs} =
      Map.pop(attrs, "schtick_ids", Map.pop(attrs, :schtick_ids, nil) |> elem(0))

    {party_ids, attrs} = Map.pop(attrs, "party_ids", Map.pop(attrs, :party_ids, nil) |> elem(0))
    {site_ids, attrs} = Map.pop(attrs, "site_ids", Map.pop(attrs, :site_ids, nil) |> elem(0))

    Multi.new()
    |> Multi.update(:character, Character.changeset(character, attrs))
    |> Multi.run(:sync_weapons, fn _repo, %{character: updated_character} ->
      sync_character_weapons(updated_character.id, weapon_ids)
    end)
    |> Multi.run(:sync_schticks, fn _repo, %{character: updated_character} ->
      sync_character_schticks(updated_character.id, schtick_ids)
    end)
    |> Multi.run(:sync_parties, fn _repo, %{character: updated_character} ->
      sync_character_parties(updated_character.id, party_ids)
    end)
    |> Multi.run(:sync_sites, fn _repo, %{character: updated_character} ->
      sync_character_sites(updated_character.id, site_ids)
    end)
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      # Preload associations before broadcasting
      character_with_associations =
        Repo.preload(character, [:user, :faction, :juncture, :image_positions])

      broadcast_change(character_with_associations, :update)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # Sync character weapons - handles adding/removing weapons via weapon_ids
  defp sync_character_weapons(_character_id, nil), do: {:ok, :skipped}

  defp sync_character_weapons(character_id, weapon_ids) when is_list(weapon_ids) do
    alias ShotElixir.Weapons.Carry

    # Get current weapon_ids for this character
    current_weapon_ids =
      from(c in Carry, where: c.character_id == ^character_id, select: c.weapon_id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    # Normalize incoming weapon_ids to strings
    new_weapon_ids = Enum.map(weapon_ids, &to_string/1)

    # Find weapons to add and remove
    to_add = new_weapon_ids -- current_weapon_ids
    to_remove = current_weapon_ids -- new_weapon_ids

    # Remove weapons that are no longer in the list
    if Enum.any?(to_remove) do
      from(c in Carry,
        where: c.character_id == ^character_id and c.weapon_id in ^to_remove
      )
      |> Repo.delete_all()
    end

    # Add new weapons
    Enum.each(to_add, fn weapon_id ->
      %Carry{}
      |> Ecto.Changeset.change(%{character_id: character_id, weapon_id: weapon_id})
      |> Repo.insert(on_conflict: :nothing)
    end)

    {:ok, :synced}
  end

  # Sync character schticks - handles adding/removing schticks via schtick_ids
  defp sync_character_schticks(_character_id, nil), do: {:ok, :skipped}

  defp sync_character_schticks(character_id, schtick_ids) when is_list(schtick_ids) do
    alias ShotElixir.Schticks.CharacterSchtick

    # Get current schtick_ids for this character
    current_schtick_ids =
      from(cs in CharacterSchtick, where: cs.character_id == ^character_id, select: cs.schtick_id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    # Normalize incoming schtick_ids to strings
    new_schtick_ids = Enum.map(schtick_ids, &to_string/1)

    # Find schticks to add and remove
    to_add = new_schtick_ids -- current_schtick_ids
    to_remove = current_schtick_ids -- new_schtick_ids

    # Remove schticks that are no longer in the list
    if Enum.any?(to_remove) do
      from(cs in CharacterSchtick,
        where: cs.character_id == ^character_id and cs.schtick_id in ^to_remove
      )
      |> Repo.delete_all()
    end

    # Add new schticks
    Enum.each(to_add, fn schtick_id ->
      %CharacterSchtick{}
      |> Ecto.Changeset.change(%{character_id: character_id, schtick_id: schtick_id})
      |> Repo.insert(on_conflict: :nothing)
    end)

    {:ok, :synced}
  end

  # Sync character parties - handles adding/removing parties via party_ids
  defp sync_character_parties(_character_id, nil), do: {:ok, :skipped}

  defp sync_character_parties(character_id, party_ids) when is_list(party_ids) do
    alias ShotElixir.Parties.Membership

    # Get current party_ids for this character
    current_party_ids =
      from(m in Membership, where: m.character_id == ^character_id, select: m.party_id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    # Normalize incoming party_ids to strings
    new_party_ids = Enum.map(party_ids, &to_string/1)

    # Find parties to add and remove
    to_add = new_party_ids -- current_party_ids
    to_remove = current_party_ids -- new_party_ids

    # Remove memberships that are no longer in the list
    if Enum.any?(to_remove) do
      from(m in Membership,
        where: m.character_id == ^character_id and m.party_id in ^to_remove
      )
      |> Repo.delete_all()
    end

    # Add new memberships
    Enum.each(to_add, fn party_id ->
      %Membership{}
      |> Ecto.Changeset.change(%{character_id: character_id, party_id: party_id})
      |> Repo.insert(on_conflict: :nothing)
    end)

    {:ok, :synced}
  end

  # Sync character sites - handles adding/removing sites via site_ids
  defp sync_character_sites(_character_id, nil), do: {:ok, :skipped}

  defp sync_character_sites(character_id, site_ids) when is_list(site_ids) do
    alias ShotElixir.Sites.Attunement

    # Get current site_ids for this character
    current_site_ids =
      from(a in Attunement, where: a.character_id == ^character_id, select: a.site_id)
      |> Repo.all()
      |> Enum.map(&to_string/1)

    # Normalize incoming site_ids to strings
    new_site_ids = Enum.map(site_ids, &to_string/1)

    # Find sites to add and remove
    to_add = new_site_ids -- current_site_ids
    to_remove = current_site_ids -- new_site_ids

    # Remove attunements that are no longer in the list
    if Enum.any?(to_remove) do
      from(a in Attunement,
        where: a.character_id == ^character_id and a.site_id in ^to_remove
      )
      |> Repo.delete_all()
    end

    # Add new attunements
    Enum.each(to_add, fn site_id ->
      %Attunement{}
      |> Ecto.Changeset.change(%{character_id: character_id, site_id: site_id})
      |> Repo.insert(on_conflict: :nothing)
    end)

    {:ok, :synced}
  end

  def delete_character(%Character{} = character) do
    Multi.new()
    |> Multi.update(:character, Ecto.Changeset.change(character, active: false))
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      # Preload associations before broadcasting
      character_with_associations =
        Repo.preload(character, [:user, :faction, :juncture, :image_positions])

      broadcast_change(character_with_associations, :delete)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
    end
  end

  def duplicate_character(%Character{} = character, user) do
    # Generate unique name for the duplicate
    unique_name = generate_unique_name(character.name, character.campaign_id)

    attrs =
      Map.from_struct(character)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.put(:name, unique_name)
      |> Map.put(:user_id, user.id)
      |> Map.put(:is_template, false)

    create_character(attrs)
  end

  # Advancement functions

  alias ShotElixir.Characters.Advancement

  @doc """
  Returns the list of advancements for a character, ordered by creation date descending.
  """
  def list_advancements(character_id) do
    query =
      from a in Advancement,
        where: a.character_id == ^character_id,
        order_by: [desc: a.created_at]

    Repo.all(query)
  end

  @doc """
  Gets a single advancement.
  Raises `Ecto.NoResultsError` if the Advancement does not exist.
  """
  def get_advancement!(id), do: Repo.get!(Advancement, id)

  @doc """
  Gets a single advancement. Returns nil if not found.
  """
  def get_advancement(id), do: Repo.get(Advancement, id)

  @doc """
  Creates an advancement for a character.
  """
  def create_advancement(character_id, attrs \\ %{}) do
    # Ensure attrs uses string keys for consistency with Ecto casting
    attrs =
      attrs
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
      |> Map.put("character_id", character_id)

    %Advancement{}
    |> Advancement.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an advancement.
  """
  def update_advancement(%Advancement{} = advancement, attrs) do
    advancement
    |> Advancement.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an advancement.
  """
  def delete_advancement(%Advancement{} = advancement) do
    Repo.delete(advancement)
  end

  @doc """
  Generates a unique character name within a campaign by appending a number if the name already exists.
  Strips any existing trailing number suffix before generating a new unique name.

  ## Examples

      iex> generate_unique_name("Carson Freeman", campaign_id)
      "Carson Freeman (1)"  # if "Carson Freeman" already exists

      iex> generate_unique_name("Carson Freeman (1)", campaign_id)
      "Carson Freeman (2)"  # strips (1) and finds next available number

      iex> generate_unique_name("New Character", campaign_id)
      "New Character"  # if name doesn't exist yet
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)

    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if the base name exists
    case Repo.exists?(
           from c in Character, where: c.campaign_id == ^campaign_id and c.name == ^base_name
         ) do
      false ->
        base_name

      true ->
        # Find the next available number
        find_next_available_name(base_name, campaign_id, 1)
    end
  end

  defp find_next_available_name(base_name, campaign_id, counter) do
    new_name = "#{base_name} (#{counter})"

    case Repo.exists?(
           from c in Character, where: c.campaign_id == ^campaign_id and c.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end
end
