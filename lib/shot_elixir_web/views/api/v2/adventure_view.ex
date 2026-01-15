defmodule ShotElixirWeb.Api.V2.AdventureView do
  def render("index.json", %{adventures: adventures, meta: meta}) do
    %{
      adventures: Enum.map(adventures, &render_adventure/1),
      meta: meta
    }
  end

  def render("show.json", %{adventure: adventure}) do
    render_adventure(adventure)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_adventure(adventure) do
    %{
      id: adventure.id,
      name: adventure.name,
      description: adventure.description,
      season: adventure.season,
      started_at: adventure.started_at,
      ended_at: adventure.ended_at,
      active: adventure.active,
      at_a_glance: adventure.at_a_glance,
      user_id: adventure.user_id,
      campaign_id: adventure.campaign_id,
      character_ids: get_character_ids(adventure),
      villain_ids: get_villain_ids(adventure),
      fight_ids: get_fight_ids(adventure),
      created_at: adventure.created_at,
      updated_at: adventure.updated_at,
      image_url: get_image_url(adventure),
      characters: render_characters_if_loaded(adventure),
      villains: render_villains_if_loaded(adventure),
      fights: render_fights_if_loaded(adventure),
      user: render_user_if_loaded(adventure),
      image_positions: render_image_positions_if_loaded(adventure),
      notion_page_id: adventure.notion_page_id,
      last_synced_to_notion_at: adventure.last_synced_to_notion_at,
      entity_class: "Adventure"
    }
  end

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(errors), do: errors

  defp get_character_ids(adventure) do
    case Map.get(adventure, :adventure_characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      adventure_characters ->
        adventure_characters
        |> Enum.map(fn ac -> ac.character_id end)
        |> Enum.filter(&(&1 != nil))
    end
  end

  defp get_villain_ids(adventure) do
    case Map.get(adventure, :adventure_villains) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      adventure_villains ->
        adventure_villains
        |> Enum.map(fn av -> av.character_id end)
        |> Enum.filter(&(&1 != nil))
    end
  end

  defp get_fight_ids(adventure) do
    case Map.get(adventure, :adventure_fights) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      adventure_fights ->
        adventure_fights
        |> Enum.map(fn af -> af.fight_id end)
        |> Enum.filter(&(&1 != nil))
    end
  end

  defp render_characters_if_loaded(adventure) do
    case Map.get(adventure, :adventure_characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      adventure_characters ->
        characters =
          adventure_characters
          |> Enum.map(fn ac -> ac.character end)
          |> Enum.filter(&(&1 != nil))

        characters_with_images = ShotElixir.ImageLoader.load_image_urls(characters, "Character")
        Enum.map(characters_with_images, &render_character_lite/1)
    end
  end

  defp render_villains_if_loaded(adventure) do
    case Map.get(adventure, :adventure_villains) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      adventure_villains ->
        villains =
          adventure_villains
          |> Enum.map(fn av -> av.character end)
          |> Enum.filter(&(&1 != nil))

        villains_with_images = ShotElixir.ImageLoader.load_image_urls(villains, "Character")
        Enum.map(villains_with_images, &render_character_lite/1)
    end
  end

  defp render_fights_if_loaded(adventure) do
    case Map.get(adventure, :adventure_fights) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      adventure_fights ->
        adventure_fights
        |> Enum.map(fn af -> af.fight end)
        |> Enum.filter(&(&1 != nil))
        |> Enum.map(&render_fight_lite/1)
    end
  end

  defp render_user_if_loaded(adventure) do
    case Map.get(adventure, :user) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      user -> render_user_lite(user)
    end
  end

  defp render_image_positions_if_loaded(adventure) do
    case Map.get(adventure, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: get_image_url(character),
      category: "character",
      entity_class: "Character"
    }
  end

  defp render_fight_lite(fight) do
    %{
      id: fight.id,
      name: fight.name,
      entity_class: "Fight"
    }
  end

  defp render_user_lite(user) do
    %{
      id: user.id,
      email: user.email,
      entity_class: "User"
    }
  end

  defp render_image_position(position) do
    %{
      id: position.id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides
    }
  end

  defp get_image_url(record) when is_map(record) do
    case Map.get(record, :image_url) do
      nil ->
        entity_type =
          case Map.get(record, :__struct__) do
            nil -> nil
            struct_module -> struct_module |> Module.split() |> List.last()
          end

        if entity_type && Map.get(record, :id) do
          ShotElixir.ActiveStorage.get_image_url(entity_type, record.id)
        else
          nil
        end

      url ->
        url
    end
  end

  defp get_image_url(_), do: nil
end
