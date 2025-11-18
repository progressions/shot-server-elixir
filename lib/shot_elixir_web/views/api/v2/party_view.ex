defmodule ShotElixirWeb.Api.V2.PartyView do
  def render("index.json", %{parties: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{parties: parties, meta: meta, is_autocomplete: is_autocomplete} ->
        party_serializer =
          if is_autocomplete, do: &render_party_autocomplete/1, else: &render_party/1

        %{
          parties: Enum.map(parties, party_serializer),
          meta: meta
        }

      %{parties: parties, meta: meta} ->
        %{
          parties: Enum.map(parties, &render_party/1),
          meta: meta
        }

      parties when is_list(parties) ->
        # Legacy format for backward compatibility
        %{
          parties: Enum.map(parties, &render_party/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(parties),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{party: party}) do
    render_party(party)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_party(party) do
    %{
      id: party.id,
      name: party.name,
      description: party.description,
      active: party.active,
      faction_id: party.faction_id,
      campaign_id: party.campaign_id,
      juncture_id: party.juncture_id,
      character_ids: get_character_ids(party),
      vehicle_ids: get_vehicle_ids(party),
      created_at: party.created_at,
      updated_at: party.updated_at,
      image_url: party.image_url,
      characters: render_characters_if_loaded(party),
      vehicles: render_vehicles_if_loaded(party),
      faction: render_faction_if_loaded(party),
      image_positions: render_image_positions_if_loaded(party),
      entity_class: "Party"
    }
  end

  defp render_party_autocomplete(party) do
    %{
      id: party.id,
      name: party.name,
      entity_class: "Party"
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

  defp get_character_ids(party) do
    case Map.get(party, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, & &1.id)
    end
  end

  defp get_vehicle_ids(party) do
    case Map.get(party, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, & &1.id)
    end
  end

  defp render_characters_if_loaded(party) do
    case Map.get(party, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, &render_character_lite/1)
    end
  end

  defp render_vehicles_if_loaded(party) do
    case Map.get(party, :vehicles) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      vehicles -> Enum.map(vehicles, &render_vehicle_lite/1)
    end
  end

  defp render_faction_if_loaded(party) do
    case Map.get(party, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_lite(faction)
    end
  end

  defp render_image_positions_if_loaded(party) do
    case Map.get(party, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      entity_class: "Character"
    }
  end

  defp render_vehicle_lite(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      entity_class: "Vehicle"
    }
  end

  defp render_faction_lite(faction) do
    %{
      id: faction.id,
      name: faction.name,
      entity_class: "Faction"
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
end