defmodule ShotElixir.Services.CampaignSeederService do
  @moduledoc """
  Service for seeding new campaigns with content from the master template campaign.

  When a user creates a new campaign, this service copies:
  - Schticks (with prerequisite linking)
  - Weapons
  - Factions
  - Junctures (with faction references)
  - Characters (template characters only, with schtick/weapon/faction/juncture associations)

  The master template campaign is identified by `is_master_template: true`.
  """

  require Logger

  alias ShotElixir.Repo
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Schticks.Schtick
  alias ShotElixir.Weapons.Weapon
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Characters.Character
  alias ShotElixir.ImagePositions.ImagePosition

  import Ecto.Query

  @doc """
  Seeds a campaign with content from the master template.
  Returns {:ok, campaign} if successful, {:error, reason} otherwise.

  Will not seed if:
  - Campaign is already seeded (has seeded_at)
  - Campaign is not persisted
  - No master template exists
  """
  def seed_campaign(%Campaign{} = campaign) do
    Logger.info(
      "[CampaignSeederService] Starting seed_campaign for: #{campaign.name} (ID: #{campaign.id})"
    )

    cond do
      campaign.seeded_at != nil ->
        Logger.info(
          "[CampaignSeederService] Campaign already seeded, seeded_at: #{campaign.seeded_at}"
        )

        {:ok, campaign}

      campaign.id == nil ->
        Logger.error("[CampaignSeederService] Campaign not persisted")
        {:error, :not_persisted}

      true ->
        case get_master_template() do
          nil ->
            Logger.error("[CampaignSeederService] No master template found!")
            {:error, :no_master_template}

          master_template ->
            Logger.info(
              "[CampaignSeederService] Found master template: #{master_template.name} (ID: #{master_template.id})"
            )

            copy_campaign_content(master_template, campaign)
        end
    end
  end

  @doc """
  Copies all content from source campaign to target campaign.
  This is the main workhorse function that coordinates all duplication.
  """
  def copy_campaign_content(%Campaign{} = source_campaign, %Campaign{} = target_campaign) do
    Logger.info(
      "[CampaignSeederService] Copying content from #{source_campaign.name} to #{target_campaign.name}"
    )

    Repo.transaction(fn ->
      # Copy in order: dependencies first
      # 1. Schticks (needed by characters)
      Logger.info("[CampaignSeederService] Starting schtick duplication...")
      {:ok, schtick_mapping} = duplicate_schticks(source_campaign, target_campaign)

      # 2. Weapons (needed by characters)
      Logger.info("[CampaignSeederService] Starting weapon duplication...")
      {:ok, _weapon_mapping} = duplicate_weapons(source_campaign, target_campaign)

      # 3. Factions (needed by junctures and characters)
      Logger.info("[CampaignSeederService] Starting faction duplication...")
      {:ok, faction_mapping} = duplicate_factions(source_campaign, target_campaign)

      # 4. Junctures (references factions)
      Logger.info("[CampaignSeederService] Starting juncture duplication...")

      {:ok, juncture_mapping} =
        duplicate_junctures(source_campaign, target_campaign, faction_mapping)

      # 5. Characters (template characters, references schticks/weapons/factions/junctures)
      Logger.info("[CampaignSeederService] Starting character duplication...")

      {:ok, _character_count} =
        duplicate_characters(source_campaign, target_campaign, faction_mapping, juncture_mapping)

      # 6. Link schtick prerequisites (now that all schticks exist in target)
      Logger.info("[CampaignSeederService] Linking schtick prerequisites...")
      link_schtick_prerequisites(schtick_mapping)

      # 7. Copy campaign image positions
      Logger.info("[CampaignSeederService] Copying image positions...")
      copy_image_positions(source_campaign, target_campaign, "Campaign")

      # 8. Mark campaign as seeded
      {:ok, updated_campaign} =
        target_campaign
        |> Ecto.Changeset.change(
          seeded_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
        )
        |> Repo.update()

      Logger.info("[CampaignSeederService] Successfully seeded campaign #{target_campaign.name}")

      updated_campaign
    end)
  end

  # Private functions

  defp get_master_template do
    Repo.get_by(Campaign, is_master_template: true)
  end

  @doc false
  def duplicate_schticks(%Campaign{} = source, %Campaign{} = target) do
    schticks =
      from(s in Schtick,
        where: s.campaign_id == ^source.id and s.active == true,
        order_by: [asc: s.created_at]
      )
      |> Repo.all()

    Logger.info("[CampaignSeederService] Duplicating #{length(schticks)} schticks")

    # We need to track old_id -> new_schtick for prerequisite linking
    mapping =
      Enum.reduce(schticks, %{}, fn schtick, acc ->
        case duplicate_schtick(schtick, target) do
          {:ok, new_schtick} ->
            Logger.debug("[CampaignSeederService] Duplicated schtick: #{new_schtick.name}")
            # Store mapping with original prerequisite_id for later linking
            Map.put(acc, schtick.id, %{
              new_schtick: new_schtick,
              original_prerequisite_id: schtick.prerequisite_id
            })

          {:error, changeset} ->
            Logger.error(
              "[CampaignSeederService] Failed to duplicate schtick #{schtick.name}: #{inspect(changeset.errors)}"
            )

            acc
        end
      end)

    {:ok, mapping}
  end

  defp duplicate_schtick(%Schtick{} = schtick, %Campaign{} = target) do
    unique_name = generate_unique_name(schtick.name, target.id, Schtick, :name)

    attrs = %{
      name: unique_name,
      description: schtick.description,
      category: schtick.category,
      path: schtick.path,
      color: schtick.color,
      bonus: schtick.bonus,
      archetypes: schtick.archetypes,
      active: true,
      campaign_id: target.id
      # prerequisite_id is set later after all schticks are created
    }

    result =
      %Schtick{}
      |> Schtick.changeset(attrs)
      |> Repo.insert()

    # Copy image positions after insert
    case result do
      {:ok, new_schtick} ->
        copy_image_positions(schtick, new_schtick, "Schtick")
        {:ok, new_schtick}

      error ->
        error
    end
  end

  defp link_schtick_prerequisites(schtick_mapping) do
    # Build a map of old_id -> new_id for looking up prerequisites
    old_to_new_id =
      Enum.reduce(schtick_mapping, %{}, fn {old_id, %{new_schtick: new_schtick}}, acc ->
        Map.put(acc, old_id, new_schtick.id)
      end)

    # Now update each schtick that had a prerequisite
    Enum.each(schtick_mapping, fn {_old_id,
                                   %{
                                     new_schtick: new_schtick,
                                     original_prerequisite_id: prereq_id
                                   }} ->
      if prereq_id do
        case Map.get(old_to_new_id, prereq_id) do
          nil ->
            Logger.warning(
              "[CampaignSeederService] Could not find new prerequisite for schtick #{new_schtick.name}"
            )

          new_prereq_id ->
            new_schtick
            |> Ecto.Changeset.change(prerequisite_id: new_prereq_id)
            |> Repo.update()
        end
      end
    end)
  end

  @doc false
  def duplicate_weapons(%Campaign{} = source, %Campaign{} = target) do
    weapons =
      from(w in Weapon,
        where: w.campaign_id == ^source.id and w.active == true,
        order_by: [asc: w.created_at]
      )
      |> Repo.all()

    Logger.info("[CampaignSeederService] Duplicating #{length(weapons)} weapons")

    mapping =
      Enum.reduce(weapons, %{}, fn weapon, acc ->
        case duplicate_weapon(weapon, target) do
          {:ok, new_weapon} ->
            Logger.debug("[CampaignSeederService] Duplicated weapon: #{new_weapon.name}")
            Map.put(acc, weapon.id, new_weapon)

          {:error, changeset} ->
            Logger.error(
              "[CampaignSeederService] Failed to duplicate weapon #{weapon.name}: #{inspect(changeset.errors)}"
            )

            acc
        end
      end)

    {:ok, mapping}
  end

  defp duplicate_weapon(%Weapon{} = weapon, %Campaign{} = target) do
    unique_name = generate_unique_name(weapon.name, target.id, Weapon, :name)

    attrs = %{
      name: unique_name,
      description: weapon.description,
      damage: weapon.damage,
      concealment: weapon.concealment,
      reload_value: weapon.reload_value,
      juncture: weapon.juncture,
      mook_bonus: weapon.mook_bonus,
      category: weapon.category,
      kachunk: weapon.kachunk,
      active: true,
      campaign_id: target.id
    }

    result =
      %Weapon{}
      |> Weapon.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, new_weapon} ->
        copy_image_positions(weapon, new_weapon, "Weapon")
        {:ok, new_weapon}

      error ->
        error
    end
  end

  @doc false
  def duplicate_factions(%Campaign{} = source, %Campaign{} = target) do
    factions =
      from(f in Faction,
        where: f.campaign_id == ^source.id and f.active == true,
        order_by: [asc: f.created_at]
      )
      |> Repo.all()

    Logger.info("[CampaignSeederService] Duplicating #{length(factions)} factions")

    mapping =
      Enum.reduce(factions, %{}, fn faction, acc ->
        case duplicate_faction(faction, target) do
          {:ok, new_faction} ->
            Logger.debug("[CampaignSeederService] Duplicated faction: #{new_faction.name}")
            Map.put(acc, faction.id, new_faction)

          {:error, changeset} ->
            Logger.error(
              "[CampaignSeederService] Failed to duplicate faction #{faction.name}: #{inspect(changeset.errors)}"
            )

            acc
        end
      end)

    {:ok, mapping}
  end

  defp duplicate_faction(%Faction{} = faction, %Campaign{} = target) do
    unique_name = generate_unique_name(faction.name, target.id, Faction, :name)

    attrs = %{
      name: unique_name,
      description: faction.description,
      active: true,
      campaign_id: target.id
    }

    result =
      %Faction{}
      |> Faction.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, new_faction} ->
        copy_image_positions(faction, new_faction, "Faction")
        {:ok, new_faction}

      error ->
        error
    end
  end

  @doc false
  def duplicate_junctures(%Campaign{} = source, %Campaign{} = target, faction_mapping) do
    junctures =
      from(j in Juncture,
        where: j.campaign_id == ^source.id and j.active == true,
        order_by: [asc: j.created_at]
      )
      |> Repo.all()

    Logger.info("[CampaignSeederService] Duplicating #{length(junctures)} junctures")

    mapping =
      Enum.reduce(junctures, %{}, fn juncture, acc ->
        case duplicate_juncture(juncture, target, faction_mapping) do
          {:ok, new_juncture} ->
            Logger.debug("[CampaignSeederService] Duplicated juncture: #{new_juncture.name}")
            Map.put(acc, juncture.id, new_juncture)

          {:error, changeset} ->
            Logger.error(
              "[CampaignSeederService] Failed to duplicate juncture #{juncture.name}: #{inspect(changeset.errors)}"
            )

            acc
        end
      end)

    {:ok, mapping}
  end

  defp duplicate_juncture(%Juncture{} = juncture, %Campaign{} = target, faction_mapping) do
    unique_name = generate_unique_name(juncture.name, target.id, Juncture, :name)

    # Map the faction_id to the new faction in the target campaign
    new_faction_id =
      if juncture.faction_id do
        case Map.get(faction_mapping, juncture.faction_id) do
          nil -> nil
          new_faction -> new_faction.id
        end
      end

    attrs = %{
      name: unique_name,
      description: juncture.description,
      active: true,
      campaign_id: target.id,
      faction_id: new_faction_id
    }

    result =
      %Juncture{}
      |> Juncture.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, new_juncture} ->
        copy_image_positions(juncture, new_juncture, "Juncture")
        {:ok, new_juncture}

      error ->
        error
    end
  end

  @doc false
  def duplicate_characters(
        %Campaign{} = source,
        %Campaign{} = target,
        faction_mapping,
        juncture_mapping
      ) do
    # Only duplicate template characters
    characters =
      from(c in Character,
        where: c.campaign_id == ^source.id and c.active == true and c.is_template == true,
        order_by: [asc: c.created_at]
      )
      |> Repo.all()
      |> Repo.preload([:schticks, :weapons])

    Logger.info("[CampaignSeederService] Duplicating #{length(characters)} template characters")

    count =
      Enum.reduce(characters, 0, fn character, acc ->
        case duplicate_character(character, target) do
          {:ok, new_character} ->
            Logger.debug("[CampaignSeederService] Duplicated character: #{new_character.name}")
            # Apply associations (schticks, weapons, faction, juncture)
            apply_character_associations(
              character,
              new_character,
              target,
              faction_mapping,
              juncture_mapping
            )

            acc + 1

          {:error, changeset} ->
            Logger.error(
              "[CampaignSeederService] Failed to duplicate character #{character.name}: #{inspect(changeset.errors)}"
            )

            acc
        end
      end)

    {:ok, count}
  end

  defp duplicate_character(%Character{} = character, %Campaign{} = target) do
    unique_name = generate_unique_name(character.name, target.id, Character, :name)

    attrs = %{
      name: unique_name,
      active: true,
      defense: character.defense,
      impairments: character.impairments || 0,
      color: character.color,
      action_values: character.action_values,
      description: character.description,
      skills: character.skills,
      status: character.status,
      task: character.task,
      summary: character.summary,
      wealth: character.wealth,
      is_template: character.is_template,
      campaign_id: target.id,
      user_id: target.user_id
      # faction_id and juncture_id are set via apply_character_associations
    }

    result =
      %Character{}
      |> Character.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, new_character} ->
        copy_image_positions(character, new_character, "Character")
        {:ok, new_character}

      error ->
        error
    end
  end

  defp apply_character_associations(
         %Character{} = source,
         %Character{} = target_character,
         %Campaign{} = target_campaign,
         faction_mapping,
         juncture_mapping
       ) do
    # Find matching schticks in target campaign by name AND category and link them
    # (unique constraint is on [:category, :name, :campaign_id])
    if source.schticks && length(source.schticks) > 0 do
      source_schtick_keys = Enum.map(source.schticks, fn s -> {s.name, s.category} end)

      target_schticks =
        from(s in Schtick,
          where:
            s.campaign_id == ^target_campaign.id and
              fragment("(?, ?) IN ?", s.name, s.category, ^source_schtick_keys)
        )
        |> Repo.all()

      # Create character_schtick associations
      Enum.each(target_schticks, fn schtick ->
        Repo.insert_all("character_schticks", [
          %{
            character_id: Ecto.UUID.dump!(target_character.id),
            schtick_id: Ecto.UUID.dump!(schtick.id),
            created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
            updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
          }
        ])
      end)
    end

    # Find matching weapons in target campaign by name and link them
    if source.weapons && length(source.weapons) > 0 do
      source_weapon_names = Enum.map(source.weapons, & &1.name)

      target_weapons =
        from(w in Weapon,
          where: w.campaign_id == ^target_campaign.id and w.name in ^source_weapon_names
        )
        |> Repo.all()

      # Create carries associations
      Enum.each(target_weapons, fn weapon ->
        Repo.insert_all("carries", [
          %{
            character_id: Ecto.UUID.dump!(target_character.id),
            weapon_id: Ecto.UUID.dump!(weapon.id),
            created_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
            updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
          }
        ])
      end)
    end

    # Use faction_mapping to look up target faction (avoids N+1 query)
    if source.faction_id do
      case Map.get(faction_mapping, source.faction_id) do
        nil ->
          :ok

        target_faction ->
          target_character
          |> Ecto.Changeset.change(faction_id: target_faction.id)
          |> Repo.update()
      end
    end

    # Use juncture_mapping to look up target juncture (avoids N+1 query)
    if source.juncture_id do
      case Map.get(juncture_mapping, source.juncture_id) do
        nil ->
          :ok

        target_juncture ->
          target_character
          |> Ecto.Changeset.change(juncture_id: target_juncture.id)
          |> Repo.update()
      end
    end
  end

  @doc """
  Copies image positions from source entity to target entity.
  """
  def copy_image_positions(source, target, positionable_type) do
    # Get source's image positions
    source_positions =
      from(ip in ImagePosition,
        where: ip.positionable_id == ^source.id and ip.positionable_type == ^positionable_type
      )
      |> Repo.all()

    Enum.each(source_positions, fn position ->
      %ImagePosition{}
      |> ImagePosition.changeset(%{
        positionable_type: positionable_type,
        positionable_id: target.id,
        context: position.context,
        x_position: position.x_position,
        y_position: position.y_position,
        style_overrides: position.style_overrides
      })
      |> Repo.insert()
    end)

    Logger.debug(
      "[CampaignSeederService] Copied #{length(source_positions)} image positions for #{positionable_type} #{target.id}"
    )
  end

  @doc """
  Generates a unique name by appending (1), (2), etc. if the name already exists.
  """
  def generate_unique_name(name, campaign_id, schema, field) when is_binary(name) do
    trimmed_name = String.trim(name)
    # Strip any existing trailing number suffix like " (1)", " (2)", etc.
    base_name = Regex.replace(~r/ \(\d+\)$/, trimmed_name, "")

    # Check if base name exists
    query =
      from(e in schema, where: field(e, ^field) == ^base_name and e.campaign_id == ^campaign_id)

    if Repo.exists?(query) do
      find_unique_name(base_name, campaign_id, schema, field, 1)
    else
      base_name
    end
  end

  defp find_unique_name(base_name, campaign_id, schema, field, counter) do
    new_name = "#{base_name} (#{counter})"

    query =
      from(e in schema, where: field(e, ^field) == ^new_name and e.campaign_id == ^campaign_id)

    if Repo.exists?(query) do
      find_unique_name(base_name, campaign_id, schema, field, counter + 1)
    else
      new_name
    end
  end
end
