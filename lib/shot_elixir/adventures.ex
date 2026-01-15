defmodule ShotElixir.Adventures do
  @moduledoc """
  The Adventures context for managing campaign storylines.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Adventures.{Adventure, AdventureCharacter, AdventureVillain, AdventureFight}
  alias ShotElixir.ImageLoader
  alias ShotElixir.Workers.ImageCopyWorker
  use ShotElixir.Models.Broadcastable

  @doc """
  Returns a list of adventures for a campaign.
  """
  def list_adventures(campaign_id) do
    query =
      from a in Adventure,
        where: a.campaign_id == ^campaign_id and a.active == true,
        order_by: [asc: fragment("lower(?)", a.name)],
        preload: [
          :user,
          :image_positions,
          adventure_characters: [:character],
          adventure_villains: [:character],
          adventure_fights: [:fight]
        ]

    query
    |> Repo.all()
    |> ImageLoader.load_image_urls("Adventure")
  end

  @doc """
  Returns paginated adventures for a campaign with filtering and sorting.
  """
  def list_campaign_adventures(campaign_id, params \\ %{}, _current_user \\ nil) do
    per_page = get_per_page(params)
    page = get_page(params)
    offset = (page - 1) * per_page

    # Base query
    query = from a in Adventure, where: a.campaign_id == ^campaign_id

    # Apply filters
    query = apply_id_filter(query, params["id"])
    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))
    query = apply_search_filter(query, params["search"])
    query = apply_visibility_filter(query, params)
    query = apply_at_a_glance_filter(query, params)
    query = apply_season_filter(query, params["season"])
    query = apply_character_filter(query, params["character_id"])
    query = apply_fight_filter(query, params["fight_id"])

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count
    count_query = build_count_query(campaign_id, params)
    total_count = Repo.aggregate(count_query, :count, :id)

    # Apply pagination and preloads
    adventures =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> preload([
        :user,
        :image_positions,
        adventure_characters: [:character],
        adventure_villains: [:character],
        adventure_fights: [:fight]
      ])
      |> Repo.all()
      |> ImageLoader.load_image_urls("Adventure")

    %{
      adventures: adventures,
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

  defp get_per_page(params) do
    case params["per_page"] do
      nil -> 15
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  defp get_page(params) do
    case params["page"] do
      nil -> 1
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  defp apply_id_filter(query, nil), do: query
  defp apply_id_filter(query, id), do: from(a in query, where: a.id == ^id)

  defp apply_ids_filter(query, _ids, false), do: query
  defp apply_ids_filter(query, nil, true), do: from(a in query, where: false)
  defp apply_ids_filter(query, [], true), do: from(a in query, where: false)

  defp apply_ids_filter(query, ids, true) when is_list(ids) do
    from(a in query, where: a.id in ^ids)
  end

  defp apply_ids_filter(query, ids, true) when is_binary(ids) do
    parsed = parse_ids(ids)

    if parsed == [],
      do: from(a in query, where: false),
      else: from(a in query, where: a.id in ^parsed)
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_search_filter(query, nil), do: query

  defp apply_search_filter(query, search) do
    search_term = "%#{search}%"
    from(a in query, where: ilike(a.name, ^search_term))
  end

  defp apply_visibility_filter(query, params) do
    case params["visibility"] do
      "hidden" -> from(a in query, where: a.active == false)
      "all" -> query
      _ -> from(a in query, where: a.active == true)
    end
  end

  defp apply_at_a_glance_filter(query, params) do
    case params["at_a_glance"] do
      "true" -> from(a in query, where: a.at_a_glance == true)
      true -> from(a in query, where: a.at_a_glance == true)
      _ -> query
    end
  end

  defp apply_season_filter(query, nil), do: query
  defp apply_season_filter(query, ""), do: query

  defp apply_season_filter(query, season) when is_binary(season) do
    case Integer.parse(season) do
      {num, _} -> from(a in query, where: a.season == ^num)
      :error -> query
    end
  end

  defp apply_season_filter(query, season) when is_integer(season) do
    from(a in query, where: a.season == ^season)
  end

  defp apply_character_filter(query, nil), do: query

  defp apply_character_filter(query, character_id) do
    from a in query,
      join: ac in "adventure_characters",
      on: ac.adventure_id == a.id,
      where: ac.character_id == ^character_id
  end

  defp apply_fight_filter(query, nil), do: query

  defp apply_fight_filter(query, fight_id) do
    from a in query,
      join: af in "adventure_fights",
      on: af.adventure_id == a.id,
      where: af.fight_id == ^fight_id
  end

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if String.downcase(params["order"] || "") == "asc", do: :asc, else: :desc

    case sort do
      "name" -> order_by(query, [a], [{^order, fragment("LOWER(?)", a.name)}, {:asc, a.id}])
      "season" -> order_by(query, [a], [{^order, a.season}, {:asc, a.id}])
      "started_at" -> order_by(query, [a], [{^order, a.started_at}, {:asc, a.id}])
      "ended_at" -> order_by(query, [a], [{^order, a.ended_at}, {:asc, a.id}])
      "created_at" -> order_by(query, [a], [{^order, a.created_at}, {:asc, a.id}])
      "updated_at" -> order_by(query, [a], [{^order, a.updated_at}, {:asc, a.id}])
      _ -> order_by(query, [a], desc: a.created_at, asc: a.id)
    end
  end

  defp build_count_query(campaign_id, params) do
    query = from a in Adventure, where: a.campaign_id == ^campaign_id

    query = apply_id_filter(query, params["id"])
    query = apply_ids_filter(query, params["ids"], Map.has_key?(params, "ids"))
    query = apply_search_filter(query, params["search"])
    query = apply_visibility_filter(query, params)
    query = apply_at_a_glance_filter(query, params)
    query = apply_season_filter(query, params["season"])
    query = apply_character_filter(query, params["character_id"])
    apply_fight_filter(query, params["fight_id"])
  end

  @doc """
  Gets a single adventure by ID.
  """
  def get_adventure!(id) do
    Adventure
    |> preload([
      :user,
      :image_positions,
      adventure_characters: [:character],
      adventure_villains: [:character],
      adventure_fights: [:fight]
    ])
    |> Repo.get!(id)
    |> ImageLoader.load_image_url("Adventure")
  end

  def get_adventure(id) do
    Adventure
    |> preload([
      :user,
      :image_positions,
      adventure_characters: [:character],
      adventure_villains: [:character],
      adventure_fights: [:fight]
    ])
    |> Repo.get(id)
    |> ImageLoader.load_image_url("Adventure")
  end

  @doc """
  Gets an adventure with character_ids, villain_ids, and fight_ids computed.
  Used by add_*/remove_* functions to return the updated adventure.
  """
  def get_adventure_with_ids!(id) do
    adventure = get_adventure!(id)

    character_ids =
      adventure.adventure_characters
      |> Enum.map(& &1.character_id)

    villain_ids =
      adventure.adventure_villains
      |> Enum.map(& &1.character_id)

    fight_ids =
      adventure.adventure_fights
      |> Enum.map(& &1.fight_id)

    %{adventure | character_ids: character_ids, villain_ids: villain_ids, fight_ids: fight_ids}
  end

  @doc """
  Creates an adventure.
  """
  def create_adventure(attrs \\ %{}) do
    %Adventure{}
    |> Adventure.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, adventure} ->
        adventure =
          Repo.preload(adventure, [
            :user,
            :image_positions,
            adventure_characters: [:character],
            adventure_villains: [:character],
            adventure_fights: [:fight]
          ])

        broadcast_change(adventure, :insert)
        {:ok, adventure}

      error ->
        error
    end
  end

  @doc """
  Updates an adventure.
  """
  def update_adventure(%Adventure{} = adventure, attrs) do
    adventure
    |> Adventure.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, adventure} ->
        # Sync character associations if character_ids is provided
        adventure =
          if Map.has_key?(attrs, "character_ids") do
            sync_characters(adventure, attrs["character_ids"])
          else
            adventure
          end

        # Sync villain associations if villain_ids is provided
        adventure =
          if Map.has_key?(attrs, "villain_ids") do
            sync_villains(adventure, attrs["villain_ids"])
          else
            adventure
          end

        # Sync fight associations if fight_ids is provided
        adventure =
          if Map.has_key?(attrs, "fight_ids") do
            sync_fights(adventure, attrs["fight_ids"])
          else
            adventure
          end

        adventure =
          Repo.preload(
            adventure,
            [
              :user,
              :image_positions,
              adventure_characters: [:character],
              adventure_villains: [:character],
              adventure_fights: [:fight]
            ],
            force: true
          )

        broadcast_change(adventure, :update)
        {:ok, adventure}

      error ->
        error
    end
  end

  @doc """
  Deletes an adventure.
  """
  def delete_adventure(%Adventure{} = adventure) do
    alias Ecto.Multi
    alias ShotElixir.ImagePositions.ImagePosition
    alias ShotElixir.Media

    adventure_with_associations =
      Repo.preload(adventure, [:user, :image_positions])

    Multi.new()
    |> Multi.delete_all(
      :delete_adventure_characters,
      from(ac in AdventureCharacter, where: ac.adventure_id == ^adventure.id)
    )
    |> Multi.delete_all(
      :delete_adventure_villains,
      from(av in AdventureVillain, where: av.adventure_id == ^adventure.id)
    )
    |> Multi.delete_all(
      :delete_adventure_fights,
      from(af in AdventureFight, where: af.adventure_id == ^adventure.id)
    )
    |> Multi.delete_all(
      :delete_image_positions,
      from(ip in ImagePosition,
        where: ip.positionable_id == ^adventure.id and ip.positionable_type == "Adventure"
      )
    )
    |> Multi.update_all(
      :orphan_images,
      Media.orphan_images_query("Adventure", adventure.id),
      []
    )
    |> Multi.delete(:adventure, adventure)
    |> Multi.run(:broadcast, fn _repo, %{adventure: deleted_adventure} ->
      broadcast_change(adventure_with_associations, :delete)
      {:ok, deleted_adventure}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{adventure: adventure}} -> {:ok, adventure}
      {:error, :adventure, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Duplicates an adventure with a unique name.
  """
  def duplicate_adventure(%Adventure{} = adventure) do
    unique_name = generate_unique_name(adventure.name, adventure.campaign_id)

    attrs =
      Map.from_struct(adventure)
      |> Map.delete(:id)
      |> Map.delete(:__meta__)
      |> Map.delete(:created_at)
      |> Map.delete(:updated_at)
      |> Map.delete(:image_url)
      |> Map.delete(:image_positions)
      |> Map.delete(:campaign)
      |> Map.delete(:user)
      |> Map.delete(:adventure_characters)
      |> Map.delete(:adventure_villains)
      |> Map.delete(:adventure_fights)
      |> Map.delete(:characters)
      |> Map.delete(:villains)
      |> Map.delete(:fights)
      |> Map.put(:name, unique_name)

    Repo.transaction(fn ->
      case create_adventure(attrs) do
        {:ok, new_adventure} ->
          queue_image_copy(adventure, new_adventure)

          # Copy character associations
          list_adventure_characters(adventure.id)
          |> Enum.each(fn ac ->
            add_character(new_adventure.id, ac.character_id)
          end)

          # Copy villain associations
          list_adventure_villains(adventure.id)
          |> Enum.each(fn av ->
            add_villain(new_adventure.id, av.character_id)
          end)

          # Copy fight associations
          list_adventure_fights(adventure.id)
          |> Enum.each(fn af ->
            add_fight(new_adventure.id, af.fight_id)
          end)

          get_adventure!(new_adventure.id)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp queue_image_copy(source, target) do
    %{
      "source_type" => "Adventure",
      "source_id" => source.id,
      "target_type" => "Adventure",
      "target_id" => target.id
    }
    |> ImageCopyWorker.new()
    |> Oban.insert()
  end

  @doc """
  Generates a unique name for an adventure within a campaign.
  """
  def generate_unique_name(name, campaign_id) when is_binary(name) and is_binary(campaign_id) do
    trimmed_name = String.trim(name)
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    case Repo.exists?(
           from a in Adventure, where: a.campaign_id == ^campaign_id and a.name == ^base_name
         ) do
      false -> base_name
      true -> find_next_available_name(base_name, campaign_id, 1)
    end
  end

  def generate_unique_name(name, _campaign_id), do: name

  defp find_next_available_name(base_name, campaign_id, counter) do
    new_name = "#{base_name} (#{counter})"

    case Repo.exists?(
           from a in Adventure, where: a.campaign_id == ^campaign_id and a.name == ^new_name
         ) do
      false -> new_name
      true -> find_next_available_name(base_name, campaign_id, counter + 1)
    end
  end

  # Character management

  def add_character(%Adventure{} = adventure, character_id) do
    add_character(adventure.id, character_id)
    |> case do
      {:ok, _} -> {:ok, get_adventure_with_ids!(adventure.id)}
      error -> error
    end
  end

  def add_character(adventure_id, character_id) when is_binary(adventure_id) do
    attrs = %{"adventure_id" => adventure_id, "character_id" => character_id}

    %AdventureCharacter{}
    |> AdventureCharacter.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, ac} ->
        broadcast_adventure_update(adventure_id)
        {:ok, ac}

      error ->
        error
    end
  end

  def remove_character(%Adventure{} = adventure, character_id) do
    remove_character(adventure.id, character_id)
    |> case do
      {:ok, _} -> {:ok, get_adventure_with_ids!(adventure.id)}
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  def remove_character(adventure_id, character_id) when is_binary(adventure_id) do
    case Repo.get_by(AdventureCharacter, adventure_id: adventure_id, character_id: character_id) do
      nil ->
        {:error, :not_found}

      ac ->
        case Repo.delete(ac) do
          {:ok, _} ->
            broadcast_adventure_update(adventure_id)
            {:ok, ac}

          error ->
            error
        end
    end
  end

  def list_adventure_characters(adventure_id) do
    from(ac in AdventureCharacter,
      where: ac.adventure_id == ^adventure_id,
      preload: [:character]
    )
    |> Repo.all()
  end

  defp sync_characters(adventure, character_ids) when is_list(character_ids) do
    current = list_adventure_characters(adventure.id)

    # Remove characters not in new list
    current
    |> Enum.filter(fn ac -> ac.character_id not in character_ids end)
    |> Enum.each(fn ac -> Repo.delete(ac) end)

    # Add new characters
    existing_ids = Enum.map(current, & &1.character_id)

    character_ids
    |> Enum.filter(fn id -> id not in existing_ids end)
    |> Enum.each(fn id -> add_character(adventure.id, id) end)

    adventure
  end

  defp sync_characters(adventure, _), do: adventure

  # Villain management

  def add_villain(%Adventure{} = adventure, character_id) do
    add_villain(adventure.id, character_id)
    |> case do
      {:ok, _} -> {:ok, get_adventure_with_ids!(adventure.id)}
      error -> error
    end
  end

  def add_villain(adventure_id, character_id) when is_binary(adventure_id) do
    attrs = %{"adventure_id" => adventure_id, "character_id" => character_id}

    %AdventureVillain{}
    |> AdventureVillain.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, av} ->
        broadcast_adventure_update(adventure_id)
        {:ok, av}

      error ->
        error
    end
  end

  def remove_villain(%Adventure{} = adventure, character_id) do
    remove_villain(adventure.id, character_id)
    |> case do
      {:ok, _} -> {:ok, get_adventure_with_ids!(adventure.id)}
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  def remove_villain(adventure_id, character_id) when is_binary(adventure_id) do
    case Repo.get_by(AdventureVillain, adventure_id: adventure_id, character_id: character_id) do
      nil ->
        {:error, :not_found}

      av ->
        case Repo.delete(av) do
          {:ok, _} ->
            broadcast_adventure_update(adventure_id)
            {:ok, av}

          error ->
            error
        end
    end
  end

  def list_adventure_villains(adventure_id) do
    from(av in AdventureVillain,
      where: av.adventure_id == ^adventure_id,
      preload: [:character]
    )
    |> Repo.all()
  end

  defp sync_villains(adventure, villain_ids) when is_list(villain_ids) do
    current = list_adventure_villains(adventure.id)

    current
    |> Enum.filter(fn av -> av.character_id not in villain_ids end)
    |> Enum.each(fn av -> Repo.delete(av) end)

    existing_ids = Enum.map(current, & &1.character_id)

    villain_ids
    |> Enum.filter(fn id -> id not in existing_ids end)
    |> Enum.each(fn id -> add_villain(adventure.id, id) end)

    adventure
  end

  defp sync_villains(adventure, _), do: adventure

  # Fight management

  def add_fight(%Adventure{} = adventure, fight_id) do
    add_fight(adventure.id, fight_id)
    |> case do
      {:ok, _} -> {:ok, get_adventure_with_ids!(adventure.id)}
      error -> error
    end
  end

  def add_fight(adventure_id, fight_id) when is_binary(adventure_id) do
    attrs = %{"adventure_id" => adventure_id, "fight_id" => fight_id}

    %AdventureFight{}
    |> AdventureFight.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, af} ->
        broadcast_adventure_update(adventure_id)
        {:ok, af}

      error ->
        error
    end
  end

  def remove_fight(%Adventure{} = adventure, fight_id) do
    remove_fight(adventure.id, fight_id)
    |> case do
      {:ok, _} -> {:ok, get_adventure_with_ids!(adventure.id)}
      {:error, :not_found} -> {:error, :not_found}
      error -> error
    end
  end

  def remove_fight(adventure_id, fight_id) when is_binary(adventure_id) do
    case Repo.get_by(AdventureFight, adventure_id: adventure_id, fight_id: fight_id) do
      nil ->
        {:error, :not_found}

      af ->
        case Repo.delete(af) do
          {:ok, _} ->
            broadcast_adventure_update(adventure_id)
            {:ok, af}

          error ->
            error
        end
    end
  end

  def list_adventure_fights(adventure_id) do
    from(af in AdventureFight,
      where: af.adventure_id == ^adventure_id,
      preload: [:fight]
    )
    |> Repo.all()
  end

  defp sync_fights(adventure, fight_ids) when is_list(fight_ids) do
    current = list_adventure_fights(adventure.id)

    current
    |> Enum.filter(fn af -> af.fight_id not in fight_ids end)
    |> Enum.each(fn af -> Repo.delete(af) end)

    existing_ids = Enum.map(current, & &1.fight_id)

    fight_ids
    |> Enum.filter(fn id -> id not in existing_ids end)
    |> Enum.each(fn id -> add_fight(adventure.id, id) end)

    adventure
  end

  defp sync_fights(adventure, _), do: adventure

  defp broadcast_adventure_update(nil), do: :ok

  defp broadcast_adventure_update(adventure_id) do
    case get_adventure(adventure_id) do
      nil -> :ok
      adventure -> broadcast_change(adventure, :update)
    end
  end
end
