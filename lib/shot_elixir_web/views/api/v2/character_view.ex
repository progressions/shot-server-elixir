defmodule ShotElixirWeb.Api.V2.CharacterView do
  def render("index.json", %{characters: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{
        characters: characters,
        archetypes: archetypes,
        meta: meta,
        is_autocomplete: is_autocomplete
      } ->
        character_serializer =
          if is_autocomplete,
            do: &render_character_autocomplete/1,
            else: &render_character_index/1

        %{
          characters: Enum.map(characters, character_serializer),
          # TODO: Include factions from query
          factions: [],
          archetypes: archetypes,
          meta: meta
        }

      %{characters: characters, archetypes: archetypes, meta: meta} ->
        %{
          characters: Enum.map(characters, &render_character_index/1),
          # TODO: Include factions from query
          factions: [],
          archetypes: archetypes,
          meta: meta
        }

      %{characters: characters, meta: meta, is_autocomplete: is_autocomplete} ->
        character_serializer =
          if is_autocomplete,
            do: &render_character_autocomplete/1,
            else: &render_character_index/1

        %{
          characters: Enum.map(characters, character_serializer),
          factions: [],
          archetypes: [],
          meta: meta
        }

      %{characters: characters, meta: meta} ->
        %{
          characters: Enum.map(characters, &render_character_index/1),
          factions: [],
          archetypes: [],
          meta: meta
        }

      characters when is_list(characters) ->
        # Legacy format for backward compatibility
        %{
          characters: Enum.map(characters, &render_character_index/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(characters),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{character: character}) do
    %{
      character: render_character_full(character)
    }
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

  # Rails CharacterIndexSerializer format
  defp render_character_index(character) do
    %{
      id: character.id,
      name: character.name,
      task: get_in(character.action_values, ["Task"]),
      image_url: get_image_url(character),
      user_id: character.user_id,
      faction_id: character.faction_id,
      action_values: character.action_values,
      created_at: character.created_at,
      active: character.active,
      entity_class: "Character",
      description: character.description,
      schtick_ids: get_association_ids(character, :schticks),
      weapon_ids: get_association_ids(character, :weapons),
      skills: character.skills,
      user: render_user_if_loaded(character),
      faction: render_faction_if_loaded(character),
      image_positions: render_image_positions_if_loaded(character)
    }
  end

  # Rails CharacterSerializer format (full detail)
  defp render_character_full(character) do
    %{
      id: character.id,
      name: character.name,
      active: character.active,
      created_at: character.created_at,
      updated_at: character.updated_at,
      campaign_id: character.campaign_id,
      action_values: character.action_values,
      faction_id: character.faction_id,
      description: character.description,
      skills: character.skills,
      category: get_in(character.action_values, ["Type"]),
      image_url: get_image_url(character),
      task: get_in(character.action_values, ["Task"]),
      notion_page_id: character.notion_page_id,
      wealth: character.wealth,
      juncture_id: character.juncture_id,
      schtick_ids: get_association_ids(character, :schticks),
      schticks: render_schticks_if_loaded(character),
      party_ids: get_association_ids(character, :parties),
      site_ids: get_association_ids(character, :sites),
      advancement_ids: get_association_ids(character, :advancements),
      weapon_ids: get_association_ids(character, :weapons),
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

  defp render_faction_if_loaded(character) do
    case Map.get(character, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_full(faction)
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

  # Rails FactionSerializer format
  defp render_faction_full(faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      image_url: get_image_url(faction),
      active: faction.active,
      created_at: faction.created_at,
      updated_at: faction.updated_at,
      entity_class: "Faction"
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
  defp get_image_url(record) do
    # TODO: Implement proper image attachment checking
    # For now, return nil like Rails when no image is attached
    Map.get(record, :image_url)
  end
end
