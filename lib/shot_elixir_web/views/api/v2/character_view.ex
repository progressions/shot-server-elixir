defmodule ShotElixirWeb.Api.V2.CharacterView do
  @default_description %{
    "Nicknames" => "",
    "Age" => "",
    "Height" => "",
    "Weight" => "",
    "Hair Color" => "",
    "Eye Color" => "",
    "Style of Dress" => "",
    "Appearance" => "",
    "Background" => "",
    "Melodramatic Hook" => ""
  }

  def render("index.json", %{
        characters: characters,
        meta: meta,
        archetypes: archetypes,
        factions: factions
      }) do
    %{
      characters: Enum.map(characters, &render_character_index/1),
      meta: meta,
      archetypes: archetypes,
      factions: Enum.map(factions, &render_faction_lite_map/1)
    }
  end

  def render("show.json", %{character: character, is_gm: is_gm}) do
    render_character_full(character, is_gm)
  end

  def render("show.json", %{character: character}) do
    # Default to false for backwards compatibility - non-GM users don't see GM-only content
    render_character_full(character, false)
  end

  def render("autocomplete.json", %{characters: characters}) do
    %{
      characters: Enum.map(characters, &render_character_autocomplete/1)
    }
  end

  def render("sync.json", %{character: character, status: status}) do
    %{
      character: render_character_full(character),
      status: status,
      message: "Character sync to Notion queued"
    }
  end

  def render("pdf.json", %{character: character, url: url}) do
    %{
      character: render_character_full(character),
      pdf_url: url,
      message: if(url, do: "PDF generated successfully", else: "PDF generation pending")
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  @doc """
  Render a character for search results or index listings.
  Public function for use by SearchView and other views.
  """
  def render_for_index(character) do
    render_character_index(character)
  end

  # Rails CharacterIndexSerializer format
  defp render_character_index(character) do
    %{
      id: character.id,
      name: character.name,
      task: character.task,
      image_url: get_image_url(character),
      user_id: character.user_id,
      faction_id: character.faction_id,
      juncture_id: character.juncture_id,
      action_values: character.action_values,
      created_at: character.created_at,
      active: character.active,
      at_a_glance: character.at_a_glance,
      extending: character.extending,
      color: character.color,
      entity_class: "Character",
      description: ensure_description_keys(character.description),
      schtick_ids: get_association_ids(character, :schticks),
      weapon_ids: get_association_ids(character, :weapons),
      equipped_weapon_id: character.equipped_weapon_id,
      skills: character.skills,
      user: render_user_if_loaded(character),
      faction: render_faction_lite_if_loaded(character),
      juncture: render_juncture_lite_if_loaded(character),
      image_positions: render_image_positions_if_loaded(character)
    }
  end

  # Rails CharacterSerializer format (full detail)
  # is_gm parameter controls whether GM-only content is included
  defp render_character_full(character, is_gm \\ false) do
    base = %{
      id: character.id,
      name: character.name,
      active: character.active,
      at_a_glance: character.at_a_glance,
      extending: character.extending,
      created_at: character.created_at,
      updated_at: character.updated_at,
      campaign_id: character.campaign_id,
      action_values: character.action_values,
      faction_id: character.faction_id,
      description: ensure_description_keys(character.description),
      skills: character.skills,
      category: get_in(character.action_values, ["Type"]),
      image_url: get_image_url(character),
      task: character.task,
      notion_page_id: character.notion_page_id,
      rich_description: character.rich_description,
      mentions: character.mentions,
      wealth: character.wealth,
      juncture_id: character.juncture_id,
      color: character.color,
      schtick_ids: get_association_ids(character, :schticks),
      schticks: render_schticks_if_loaded(character),
      party_ids: get_association_ids(character, :parties),
      site_ids: get_association_ids(character, :sites),
      advancement_ids: get_association_ids(character, :advancements),
      weapon_ids: get_association_ids(character, :weapons),
      equipped_weapon_id: character.equipped_weapon_id,
      weapons: render_weapons_if_loaded(character),
      entity_class: "Character",
      user_id: character.user_id,
      is_template: character.is_template,
      impairments: character.impairments,
      user: render_user_lite_if_loaded(character),
      faction: render_faction_lite_if_loaded(character),
      juncture: render_juncture_lite_if_loaded(character),
      image_positions: render_image_positions_if_loaded(character)
    }

    # Only include GM-only content for gamemasters
    if is_gm do
      Map.put(base, :rich_description_gm_only, character.rich_description_gm_only)
    else
      base
    end
  end

  # Rails CharacterAutocompleteSerializer format
  defp render_character_autocomplete(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  # Helper functions for associations
  defp render_user_if_loaded(character) do
    case Map.get(character, :user) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      user -> render_user_full(user)
    end
  end

  defp render_user_lite_if_loaded(character) do
    case Map.get(character, :user) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      user -> render_user_lite(user)
    end
  end

  defp render_faction_lite_if_loaded(character) do
    case Map.get(character, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_lite(faction)
    end
  end

  defp render_juncture_lite_if_loaded(character) do
    case Map.get(character, :juncture) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      juncture -> render_juncture_lite(juncture)
    end
  end

  defp render_image_positions_if_loaded(character) do
    case Map.get(character, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_schticks_if_loaded(character) do
    case Map.get(character, :schticks) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      schticks -> Enum.map(schticks, &render_schtick_lite/1)
    end
  end

  defp render_weapons_if_loaded(character) do
    case Map.get(character, :weapons) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      weapons -> Enum.map(weapons, &render_weapon_lite/1)
    end
  end

  # Rails UserSerializer format for index
  defp render_user_full(user) do
    %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      image_url: get_image_url(user),
      email: user.email,
      name: "#{user.first_name} #{user.last_name}",
      gamemaster: user.gamemaster,
      admin: user.admin,
      entity_class: "User",
      active: user.active,
      at_a_glance: user.at_a_glance,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  # Rails UserLiteSerializer format
  defp render_user_lite(user) do
    %{
      id: user.id,
      name: "#{user.first_name} #{user.last_name}",
      email: user.email,
      entity_class: "User"
    }
  end

  # Rails FactionLiteSerializer format
  defp render_faction_lite(faction) do
    %{
      id: faction.id,
      name: faction.name,
      entity_class: "Faction"
    }
  end

  # Render faction from map (returned by get_factions_by_ids)
  defp render_faction_lite_map(%{id: id, name: name}) do
    %{
      id: id,
      name: name,
      entity_class: "Faction"
    }
  end

  # Rails JunctureLiteSerializer format
  defp render_juncture_lite(juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      entity_class: "Juncture"
    }
  end

  # Rails ImagePositionSerializer format
  defp render_image_position(position) do
    %{
      id: position.id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides
    }
  end

  defp render_schtick_lite(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      category: schtick.category
    }
  end

  defp render_weapon_lite(weapon) do
    %{
      id: weapon.id,
      name: weapon.name,
      damage: weapon.damage
    }
  end

  # Helper to get association IDs
  defp get_association_ids(record, association) do
    case Map.get(record, association) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      items when is_list(items) -> Enum.map(items, & &1.id)
      _ -> []
    end
  end

  # Rails-compatible image URL handling
  defp get_image_url(record) when is_map(record) do
    # Check if image_url is already in the record (pre-loaded)
    case Map.get(record, :image_url) do
      nil ->
        # Try to get entity type from struct, fallback to nil if plain map
        entity_type =
          case Map.get(record, :__struct__) do
            # Plain map, skip ActiveStorage lookup
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

  # Ensure description has all required keys with default values
  defp ensure_description_keys(description) when is_map(description) do
    Map.merge(@default_description, description)
  end

  defp ensure_description_keys(_), do: @default_description
end
