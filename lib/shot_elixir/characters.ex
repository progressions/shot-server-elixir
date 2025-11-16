defmodule ShotElixir.Characters do
  @moduledoc """
  The Characters context for managing Feng Shui 2 characters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias ShotElixir.Fights.Shot
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

    # Base query with visibility filtering
    query =
      if params["fight_id"] do
        from c in Character, where: c.active == true
      else
        from c in Character,
          where: c.campaign_id == ^campaign_id and c.active == true
      end

    # Apply template filtering (admin-only feature)
    query = apply_template_filter(query, params, current_user)

    # Apply basic filters
    query =
      if params["id"] do
        from c in query, where: c.id == ^params["id"]
      else
        query
      end

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from c in query, where: c.id in ^ids
      else
        query
      end

    query =
      if params["search"] do
        from c in query, where: ilike(c.name, ^"%#{params["search"]}%")
      else
        query
      end

    query =
      if params["character_type"] do
        from c in query,
          where: fragment("?->>'Type' = ?", c.action_values, ^params["character_type"])
      else
        query
      end

    query =
      if params["archetype"] do
        archetype_value = if params["archetype"] == "__NONE__", do: "", else: params["archetype"]
        from c in query, where: fragment("?->>'Archetype' = ?", c.action_values, ^archetype_value)
      else
        query
      end

    # Relationship filters
    query =
      if params["faction_id"] do
        if params["faction_id"] == "__NONE__" do
          from c in query, where: is_nil(c.faction_id)
        else
          from c in query, where: c.faction_id == ^params["faction_id"]
        end
      else
        query
      end

    query =
      if params["juncture_id"] do
        if params["juncture_id"] == "__NONE__" do
          from c in query, where: is_nil(c.juncture_id)
        else
          from c in query, where: c.juncture_id == ^params["juncture_id"]
        end
      else
        query
      end

    query =
      if params["user_id"] do
        from c in query, where: c.user_id == ^params["user_id"]
      else
        query
      end

    # Association-based filters
    query =
      if params["party_id"] do
        from c in query,
          join: m in "memberships",
          on: m.character_id == c.id,
          where: m.party_id == ^params["party_id"]
      else
        query
      end

    query =
      if params["fight_id"] do
        from c in query,
          join: s in Shot,
          on: s.character_id == c.id,
          where: s.fight_id == ^params["fight_id"]
      else
        query
      end

    query =
      if params["site_id"] do
        from c in query,
          join: a in "attunements",
          on: a.character_id == c.id,
          where: a.site_id == ^params["site_id"]
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination
    total_count =
      query
      |> exclude(:order_by)
      |> select([c], count(c.id))
      |> Repo.one()

    # Apply pagination
    characters =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Return characters with pagination metadata
    %{
      characters: characters,
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
    # Template filtering - only admins can access templates
    # Non-admin users (gamemasters and players) should never see templates
    is_admin = current_user && current_user.admin

    template_filter = params["template_filter"] || params["is_template"]

    if !is_admin do
      # Non-admin users always get non-templates only
      from c in query, where: c.is_template in [false, nil]
    else
      # Admin users can use template filtering
      case template_filter do
        "templates" ->
          from c in query, where: c.is_template == true

        "all" ->
          query

        "true" ->
          from c in query, where: c.is_template == true

        "false" ->
          from c in query, where: c.is_template in [false, nil]

        nil ->
          from c in query, where: c.is_template in [false, nil]

        "" ->
          from c in query, where: c.is_template in [false, nil]

        _ ->
          # Invalid value defaults to non-templates
          from c in query, where: c.is_template in [false, nil]
      end
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
    order = if params["order"] == "ASC", do: :asc, else: :desc

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

  def get_character!(id), do: Repo.get!(Character, id)
  def get_character(id), do: Repo.get(Character, id)

  def create_character(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:character, Character.changeset(%Character{}, attrs))
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      broadcast_change(character, :insert)
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
      broadcast_change(character, :update)
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
      broadcast_change(character, :delete)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
    end
  end

  def duplicate_character(%Character{} = character, user) do
    attrs =
      Map.from_struct(character)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.put(:name, "#{character.name} (Copy)")
      |> Map.put(:user_id, user.id)

    create_character(attrs)
  end
end
