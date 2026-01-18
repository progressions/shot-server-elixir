defmodule ShotElixirWeb.Api.V2.SearchView do
  @moduledoc """
  View for rendering search results with full entity data.

  Each entity type is rendered with the same format as its index view,
  enabling the frontend to use existing badge components.
  """

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

  def render("index.json", %{results: results, meta: meta}) do
    %{
      results: render_results(results),
      meta: meta
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  # Render results map, converting atom keys to string keys for JSON
  defp render_results(results) do
    results
    |> Enum.map(fn {type, items} ->
      {Atom.to_string(type), render_items_for_type(type, items)}
    end)
    |> Map.new()
  end

  defp render_items_for_type(:characters, items), do: Enum.map(items, &render_character/1)
  defp render_items_for_type(:vehicles, items), do: Enum.map(items, &render_vehicle/1)
  defp render_items_for_type(:fights, items), do: Enum.map(items, &render_fight/1)
  defp render_items_for_type(:sites, items), do: Enum.map(items, &render_site/1)
  defp render_items_for_type(:parties, items), do: Enum.map(items, &render_party/1)
  defp render_items_for_type(:factions, items), do: Enum.map(items, &render_faction/1)
  defp render_items_for_type(:schticks, items), do: Enum.map(items, &render_schtick/1)
  defp render_items_for_type(:weapons, items), do: Enum.map(items, &render_weapon/1)
  defp render_items_for_type(:junctures, items), do: Enum.map(items, &render_juncture/1)
  defp render_items_for_type(:adventures, items), do: Enum.map(items, &render_adventure/1)

  # =============================================================================
  # Character rendering (matches CharacterView.render_character_index)
  # =============================================================================

  defp render_character(character) do
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
      skills: character.skills,
      faction: render_faction_lite_if_loaded(character)
    }
  end

  # =============================================================================
  # Vehicle rendering (matches VehicleView.render_vehicle)
  # =============================================================================

  defp render_vehicle(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      description: vehicle.description,
      image_url: get_image_url(vehicle),
      color: vehicle.color,
      impairments: vehicle.impairments,
      campaign_id: vehicle.campaign_id,
      user_id: vehicle.user_id,
      faction_id: vehicle.faction_id,
      juncture_id: vehicle.juncture_id,
      action_values: vehicle.action_values,
      active: vehicle.active,
      at_a_glance: vehicle.at_a_glance,
      task: vehicle.task,
      created_at: vehicle.created_at,
      updated_at: vehicle.updated_at,
      entity_class: "Vehicle",
      faction: render_faction_lite_if_loaded(vehicle)
    }
  end

  # =============================================================================
  # Fight rendering (matches FightView.render_fight)
  # =============================================================================

  defp render_fight(fight) do
    %{
      id: fight.id,
      name: fight.name,
      description: fight.description,
      image_url: get_image_url(fight),
      created_at: fight.created_at,
      updated_at: fight.updated_at,
      active: fight.active,
      sequence: fight.sequence,
      characters: render_fight_characters(fight),
      character_ids: get_fight_character_ids(fight),
      entity_class: "Fight",
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      season: fight.season,
      session: fight.session,
      at_a_glance: fight.at_a_glance,
      campaign_id: fight.campaign_id
    }
  end

  defp render_fight_characters(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      shots ->
        shots
        |> Enum.map(& &1.character)
        |> Enum.reject(&is_nil/1)
        |> ShotElixir.ImageLoader.load_image_urls("Character")
        |> Enum.map(&render_character_lite/1)
    end
  end

  defp get_fight_character_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      shots ->
        shots
        |> Enum.map(& &1.character_id)
        |> Enum.reject(&is_nil/1)
    end
  end

  # =============================================================================
  # Site rendering (matches SiteView.render_site)
  # =============================================================================

  defp render_site(site) do
    %{
      id: site.id,
      name: site.name,
      description: site.description,
      active: site.active,
      at_a_glance: site.at_a_glance,
      faction_id: site.faction_id,
      campaign_id: site.campaign_id,
      created_at: site.created_at,
      updated_at: site.updated_at,
      image_url: get_image_url(site),
      characters: render_site_characters(site),
      character_ids: get_site_character_ids(site),
      faction: render_faction_lite_if_loaded(site),
      entity_class: "Site"
    }
  end

  defp render_site_characters(site) do
    case Map.get(site, :attunements) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      attunements ->
        attunements
        |> Enum.map(& &1.character)
        |> Enum.reject(&is_nil/1)
        |> ShotElixir.ImageLoader.load_image_urls("Character")
        |> Enum.map(&render_character_lite/1)
    end
  end

  defp get_site_character_ids(site) do
    case Map.get(site, :attunements) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      attunements ->
        attunements
        |> Enum.map(& &1.character)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.id)
    end
  end

  # =============================================================================
  # Party rendering (matches PartyView.render_party)
  # =============================================================================

  defp render_party(party) do
    %{
      id: party.id,
      name: party.name,
      description: party.description,
      active: party.active,
      at_a_glance: party.at_a_glance,
      faction_id: party.faction_id,
      campaign_id: party.campaign_id,
      created_at: party.created_at,
      updated_at: party.updated_at,
      image_url: get_image_url(party),
      characters: render_party_characters(party),
      character_ids: get_party_character_ids(party),
      faction: render_faction_lite_if_loaded(party),
      entity_class: "Party"
    }
  end

  defp render_party_characters(party) do
    case Map.get(party, :memberships) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      memberships ->
        memberships
        |> Enum.map(& &1.character)
        |> Enum.reject(&is_nil/1)
        |> ShotElixir.ImageLoader.load_image_urls("Character")
        |> Enum.map(&render_character_lite/1)
    end
  end

  defp get_party_character_ids(party) do
    case Map.get(party, :memberships) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      memberships ->
        memberships
        |> Enum.map(& &1.character)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.id)
    end
  end

  # =============================================================================
  # Faction rendering (matches FactionView.render_faction)
  # =============================================================================

  defp render_faction(faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description,
      active: faction.active,
      at_a_glance: faction.at_a_glance,
      campaign_id: faction.campaign_id,
      created_at: faction.created_at,
      updated_at: faction.updated_at,
      image_url: get_image_url(faction),
      characters: render_faction_characters(faction),
      character_ids: get_faction_character_ids(faction),
      entity_class: "Faction"
    }
  end

  defp render_faction_characters(faction) do
    case Map.get(faction, :characters) do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        []

      characters ->
        characters
        |> ShotElixir.ImageLoader.load_image_urls("Character")
        |> Enum.map(&render_character_lite/1)
    end
  end

  defp get_faction_character_ids(faction) do
    case Map.get(faction, :characters) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      characters -> Enum.map(characters, & &1.id)
    end
  end

  # =============================================================================
  # Schtick rendering (matches SchtickView pattern)
  # =============================================================================

  defp render_schtick(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      description: schtick.description,
      category: schtick.category,
      path: schtick.path,
      color: schtick.color,
      image_url: get_image_url(schtick),
      campaign_id: schtick.campaign_id,
      active: schtick.active,
      at_a_glance: schtick.at_a_glance,
      created_at: schtick.created_at,
      updated_at: schtick.updated_at,
      entity_class: "Schtick"
    }
  end

  # =============================================================================
  # Weapon rendering (matches WeaponView.render_weapon)
  # =============================================================================

  defp render_weapon(weapon) do
    %{
      id: weapon.id,
      name: weapon.name,
      description: weapon.description,
      damage: weapon.damage,
      concealment: weapon.concealment,
      reload_value: weapon.reload_value,
      juncture: weapon.juncture,
      mook_bonus: weapon.mook_bonus,
      category: weapon.category,
      kachunk: weapon.kachunk,
      image_url: get_image_url(weapon),
      active: weapon.active,
      at_a_glance: weapon.at_a_glance,
      campaign_id: weapon.campaign_id,
      entity_class: "Weapon",
      created_at: weapon.created_at,
      updated_at: weapon.updated_at
    }
  end

  # =============================================================================
  # Juncture rendering (matches JunctureView pattern)
  # =============================================================================

  defp render_juncture(juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description,
      active: juncture.active,
      at_a_glance: juncture.at_a_glance,
      faction_id: juncture.faction_id,
      campaign_id: juncture.campaign_id,
      created_at: juncture.created_at,
      updated_at: juncture.updated_at,
      image_url: get_image_url(juncture),
      faction: render_faction_lite_if_loaded(juncture),
      entity_class: "Juncture"
    }
  end

  # =============================================================================
  # Adventure rendering (matches AdventureView pattern)
  # =============================================================================

  defp render_adventure(adventure) do
    %{
      id: adventure.id,
      name: adventure.name,
      description: adventure.description,
      season: adventure.season,
      active: adventure.active,
      at_a_glance: adventure.at_a_glance,
      started_at: adventure.started_at,
      ended_at: adventure.ended_at,
      campaign_id: adventure.campaign_id,
      created_at: adventure.created_at,
      updated_at: adventure.updated_at,
      image_url: get_image_url(adventure),
      entity_class: "Adventure"
    }
  end

  # =============================================================================
  # Shared helpers
  # =============================================================================

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  defp render_faction_lite_if_loaded(entity) do
    case Map.get(entity, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      faction -> render_faction_lite(faction)
    end
  end

  defp render_faction_lite(faction) do
    %{
      id: faction.id,
      name: faction.name,
      entity_class: "Faction"
    }
  end

  # Rails-compatible image URL handling
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

  # Ensure description has all required keys with default values
  defp ensure_description_keys(description) when is_map(description) do
    Map.merge(@default_description, description)
  end

  defp ensure_description_keys(_), do: @default_description

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

  defp translate_errors(error), do: error
end
