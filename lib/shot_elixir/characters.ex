defmodule ShotElixir.Characters do
  @moduledoc """
  The Characters context for managing Feng Shui 2 characters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias ShotElixir.Fights.Shot
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

    # Apply ids filter if present
    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from c in query, where: c.id in ^ids
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

    # Return characters with pagination metadata and archetypes
    %{
      characters: characters_with_images,
      archetypes: archetypes,
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

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_sorting(query, params) do
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
    |> Repo.preload([:image_positions])
    |> ImageLoader.load_image_url("Character")
  end

  def get_character(id) do
    Repo.get(Character, id)
    |> Repo.preload([:image_positions])
    |> ImageLoader.load_image_url("Character")
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
    Multi.new()
    |> Multi.update(:character, Character.changeset(character, attrs))
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
    end
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
    case Repo.exists?(from c in Character, where: c.campaign_id == ^campaign_id and c.name == ^base_name) do
      false ->
        base_name

      true ->
        # Find the next available number
        find_next_available_name(base_name, campaign_id, 1)
    end
  end

  defp find_next_available_name(base_name, campaign_id, counter) do
    new_name = "#{base_name} (#{counter})"

    case Repo.exists?(from c in Character, where: c.campaign_id == ^campaign_id and c.name == ^new_name) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end
end
