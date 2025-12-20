defmodule ShotElixir.Repo.Migrations.CreateBaselineSchema do
  use Ecto.Migration

  @moduledoc """
  Baseline migration that creates all core tables for the shot-elixir application.
  This migration is CONDITIONAL - it only runs on fresh databases.

  For existing databases (production, dev environments that used Rails structure.sql),
  this migration will detect the tables already exist and skip creation.

  This makes the Elixir application fully standalone while remaining compatible
  with existing deployments.
  """

  def up do
    # Check if this is an existing database by looking for the users table
    # If it exists, skip this entire migration
    if table_exists?("users") do
      # Database already set up (via Rails or previous run), skip
      :ok
    else
      create_baseline_schema()
    end
  end

  def down do
    # Only drop if we created the tables (check for Ecto-style FK names)
    if constraint_exists?("campaigns", "campaigns_user_id_fkey") do
      drop_baseline_schema()
    end
  end

  defp table_exists?(table_name) do
    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name = '#{table_name}'
    )
    """

    %{rows: [[exists]]} = repo().query!(query)
    exists
  end

  defp constraint_exists?(table_name, constraint_name) do
    query = """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = '#{constraint_name}'
      AND table_name = '#{table_name}'
    )
    """

    %{rows: [[exists]]} = repo().query!(query)
    exists
  end

  defp create_baseline_schema do
    # Enable pgcrypto extension for UUID generation
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"

    # ===================
    # Core Tables (no FKs initially due to circular dependencies)
    # ===================

    # Users table (create without current_campaign_id FK initially)
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :first_name, :string, null: false, default: ""
      add :last_name, :string, null: false, default: ""
      add :email, :string, null: false, default: ""
      add :encrypted_password, :string, null: false, default: ""
      add :reset_password_token, :string
      add :reset_password_sent_at, :naive_datetime_usec
      add :remember_created_at, :naive_datetime_usec
      add :jti, :string, null: false
      add :avatar_url, :string
      add :admin, :boolean
      add :gamemaster, :boolean
      add :confirmation_token, :string
      add :confirmed_at, :naive_datetime_usec
      add :confirmation_sent_at, :naive_datetime_usec
      add :unconfirmed_email, :string
      add :failed_attempts, :integer, null: false, default: 0
      add :unlock_token, :string
      add :locked_at, :naive_datetime_usec
      # FK added later
      add :current_campaign_id, :uuid
      add :name, :string
      add :active, :boolean, null: false, default: true
      # FK added later
      add :pending_invitation_id, :uuid

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:jti])
    create unique_index(:users, [:confirmation_token])
    create unique_index(:users, [:reset_password_token])
    create unique_index(:users, [:unlock_token])
    create index(:users, [:pending_invitation_id])
    execute "CREATE INDEX index_users_on_lower_name ON users (lower(name))"

    # Campaigns table
    create table(:campaigns, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid), null: false
      add :description, :text
      add :name, :string
      add :active, :boolean, null: false, default: true
      add :is_master_template, :boolean, null: false, default: false
      add :seeded_at, :naive_datetime_usec

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:campaigns, [:user_id])
    create index(:campaigns, [:active, :created_at])
    execute "CREATE INDEX index_campaigns_on_lower_name ON campaigns (lower(name))"

    # Now add the current_campaign_id FK to users
    alter table(:users) do
      modify :current_campaign_id, references(:campaigns, type: :uuid, on_delete: :nilify_all),
        from: :uuid
    end

    create index(:users, [:current_campaign_id])

    # Factions table
    create table(:factions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string
      add :description, :text
      add :campaign_id, references(:campaigns, type: :uuid), null: false
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:factions, [:campaign_id])
    create index(:factions, [:active])
    create index(:factions, [:campaign_id, :active])
    execute "CREATE INDEX index_factions_on_lower_name ON factions (lower(name))"

    # Junctures table
    create table(:junctures, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string
      add :description, :text
      add :active, :boolean, null: false, default: true
      add :faction_id, references(:factions, type: :uuid)
      add :notion_page_id, :uuid
      add :campaign_id, references(:campaigns, type: :uuid)

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:junctures, [:campaign_id])
    create index(:junctures, [:active])
    create index(:junctures, [:campaign_id, :active])
    create index(:junctures, [:faction_id])
    execute "CREATE INDEX index_junctures_on_lower_name ON junctures (lower(name))"

    # Characters table
    create table(:characters, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :defense, :integer
      add :impairments, :integer
      add :color, :string
      add :user_id, references(:users, type: :uuid)
      add :action_values, :jsonb
      add :campaign_id, references(:campaigns, type: :uuid)
      add :active, :boolean, null: false, default: true
      add :description, :jsonb
      add :skills, :jsonb
      add :faction_id, references(:factions, type: :uuid)
      add :task, :boolean
      add :notion_page_id, :uuid
      add :last_synced_to_notion_at, :naive_datetime_usec
      add :summary, :string
      add :juncture_id, references(:junctures, type: :uuid)
      add :wealth, :string
      add :is_template, :boolean
      add :status, :jsonb, default: "[]"

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:characters, [:user_id])
    create index(:characters, [:campaign_id])
    create index(:characters, [:active])
    create index(:characters, [:campaign_id, :active])
    create index(:characters, [:campaign_id, :active, :created_at])
    create index(:characters, [:faction_id])
    create index(:characters, [:juncture_id])
    create index(:characters, [:created_at])

    execute "CREATE INDEX index_characters_on_action_values ON characters USING gin (action_values)"

    execute "CREATE INDEX index_characters_on_status ON characters USING gin (status)"
    execute "CREATE INDEX index_characters_on_lower_name ON characters (lower(name))"

    # Vehicles table
    create table(:vehicles, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :action_values, :jsonb, null: false
      add :user_id, references(:users, type: :uuid)
      add :color, :string
      add :impairments, :integer
      add :campaign_id, references(:campaigns, type: :uuid)
      add :active, :boolean, null: false, default: true
      add :faction_id, references(:factions, type: :uuid)
      add :task, :boolean
      add :notion_page_id, :uuid
      add :last_synced_to_notion_at, :naive_datetime_usec
      add :summary, :string
      add :juncture_id, references(:junctures, type: :uuid)
      add :description, :jsonb

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:vehicles, [:user_id])
    create index(:vehicles, [:campaign_id])
    create index(:vehicles, [:active])
    create index(:vehicles, [:campaign_id, :active])
    create index(:vehicles, [:campaign_id, :active, :created_at])
    create index(:vehicles, [:faction_id])
    create index(:vehicles, [:juncture_id])
    execute "CREATE INDEX index_vehicles_on_lower_name ON vehicles (lower(name))"

    # Fights table
    create table(:fights, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string
      add :sequence, :integer, null: false, default: 0
      add :campaign_id, references(:campaigns, type: :uuid)
      add :active, :boolean, null: false, default: true
      add :archived, :boolean, null: false, default: false
      add :description, :text
      add :server_id, :bigint
      add :fight_message_id, :string
      add :channel_id, :bigint
      add :started_at, :naive_datetime_usec
      add :ended_at, :naive_datetime_usec
      add :season, :integer
      add :session, :integer
      add :action_id, :uuid

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:fights, [:campaign_id])
    create index(:fights, [:active])
    create index(:fights, [:campaign_id, :active])
    execute "CREATE INDEX index_fights_on_lower_name ON fights (lower(name))"

    # Sites table
    create table(:sites, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :description, :text
      add :campaign_id, references(:campaigns, type: :uuid)
      add :name, :string
      add :faction_id, references(:factions, type: :uuid)
      add :juncture_id, references(:junctures, type: :uuid)
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:sites, [:campaign_id])
    create index(:sites, [:active])
    create index(:sites, [:campaign_id, :active])
    create index(:sites, [:faction_id])
    create index(:sites, [:juncture_id])
    create unique_index(:sites, [:campaign_id, :name])
    execute "CREATE INDEX index_sites_on_lower_name ON sites (lower(name))"

    # Parties table
    create table(:parties, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string
      add :description, :text
      add :campaign_id, references(:campaigns, type: :uuid), null: false
      add :faction_id, references(:factions, type: :uuid)
      add :juncture_id, references(:junctures, type: :uuid)
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:parties, [:campaign_id])
    create index(:parties, [:active])
    create index(:parties, [:campaign_id, :active])
    create index(:parties, [:faction_id])
    create index(:parties, [:juncture_id])
    execute "CREATE INDEX index_parties_on_lower_name ON parties (lower(name))"

    # Weapons table
    create table(:weapons, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :campaign_id, references(:campaigns, type: :uuid), null: false
      add :name, :string, null: false
      add :description, :text
      add :damage, :integer, null: false
      add :concealment, :integer
      add :reload_value, :integer
      add :juncture, :string
      add :mook_bonus, :integer, null: false, default: 0
      add :category, :string
      add :kachunk, :boolean
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:weapons, [:campaign_id])
    create index(:weapons, [:active])
    create index(:weapons, [:campaign_id, :active])
    create unique_index(:weapons, [:campaign_id, :name])
    execute "CREATE INDEX index_weapons_on_lower_name ON weapons (lower(name))"

    # Schticks table
    create table(:schticks, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :campaign_id, references(:campaigns, type: :uuid), null: false
      add :description, :text
      add :prerequisite_id, references(:schticks, type: :uuid)
      add :category, :string
      add :path, :string
      add :color, :string
      add :bonus, :boolean
      add :archetypes, :jsonb
      add :name, :string
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:schticks, [:campaign_id])
    create index(:schticks, [:active])
    create index(:schticks, [:campaign_id, :active])
    create index(:schticks, [:prerequisite_id])
    create unique_index(:schticks, [:category, :name, :campaign_id])
    execute "CREATE INDEX index_schticks_on_lower_name ON schticks (lower(name))"

    # Shots table
    create table(:shots, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :fight_id, references(:fights, type: :uuid), null: false
      add :character_id, references(:characters, type: :uuid)
      add :vehicle_id, references(:vehicles, type: :uuid)
      add :shot, :integer
      add :position, :string
      add :count, :integer, default: 0
      add :color, :string
      # Self-reference, FK added later
      add :driver_id, :uuid
      add :impairments, :integer, default: 0
      # Self-reference, FK added later
      add :driving_id, :uuid
      add :location, :string
      add :was_rammed_or_damaged, :boolean, null: false, default: false

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:shots, [:fight_id])
    create index(:shots, [:character_id])
    create index(:shots, [:vehicle_id])
    create index(:shots, [:was_rammed_or_damaged])

    # Add self-referencing FKs to shots
    alter table(:shots) do
      modify :driver_id, references(:shots, type: :uuid), from: :uuid
      modify :driving_id, references(:shots, type: :uuid), from: :uuid
    end

    create index(:shots, [:driver_id])
    create index(:shots, [:driving_id])

    # Invitations table
    create table(:invitations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :campaign_id, references(:campaigns, type: :uuid), null: false
      add :user_id, references(:users, type: :uuid), null: false
      add :email, :string
      add :pending_user_id, references(:users, type: :uuid)
      add :maximum_count, :integer
      add :remaining_count, :integer

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:invitations, [:campaign_id])
    create index(:invitations, [:user_id])
    create index(:invitations, [:pending_user_id])
    create unique_index(:invitations, [:campaign_id, :email])
    create unique_index(:invitations, [:campaign_id, :pending_user_id])

    # Now add pending_invitation_id FK to users
    alter table(:users) do
      modify :pending_invitation_id, references(:invitations, type: :uuid), from: :uuid
    end

    # ===================
    # Join/Association Tables
    # ===================

    # Advancements table
    create table(:advancements, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :character_id, references(:characters, type: :uuid), null: false
      add :description, :text

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:advancements, [:character_id])

    # Attunements table (uses integer id, not UUID)
    create table(:attunements, primary_key: false) do
      add :id, :serial, primary_key: true
      add :character_id, references(:characters, type: :uuid), null: false
      add :site_id, references(:sites, type: :uuid), null: false

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:attunements, [:character_id])
    create index(:attunements, [:site_id])
    create unique_index(:attunements, [:character_id, :site_id])

    # Campaign memberships table
    create table(:campaign_memberships, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid), null: false
      add :campaign_id, references(:campaigns, type: :uuid), null: false

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:campaign_memberships, [:user_id])
    create index(:campaign_memberships, [:campaign_id])
    create index(:campaign_memberships, [:campaign_id, :user_id])
    create index(:campaign_memberships, [:user_id, :created_at])

    # Carries table (character-weapon join)
    create table(:carries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :character_id, references(:characters, type: :uuid), null: false
      add :weapon_id, references(:weapons, type: :uuid), null: false

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:carries, [:character_id])
    create index(:carries, [:weapon_id])

    # Character effects table
    # Note: shot_id FK uses on_delete: :delete_all to match what migration 20251122120000 sets up
    create table(:character_effects, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :character_id, references(:characters, type: :uuid)
      add :vehicle_id, references(:vehicles, type: :uuid)
      add :description, :text
      add :severity, :string, null: false, default: "info"
      add :change, :string
      add :action_value, :string
      add :name, :string
      add :shot_id, references(:shots, type: :uuid, on_delete: :delete_all)

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:character_effects, [:character_id])
    create index(:character_effects, [:vehicle_id])
    create index(:character_effects, [:shot_id])

    # Character schticks table (uses integer id, not UUID)
    create table(:character_schticks, primary_key: false) do
      add :id, :serial, primary_key: true
      add :character_id, references(:characters, type: :uuid), null: false
      add :schtick_id, references(:schticks, type: :uuid), null: false

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:character_schticks, [:character_id])
    create index(:character_schticks, [:schtick_id])
    create unique_index(:character_schticks, [:character_id, :schtick_id])

    # Chase relationships table
    create table(:chase_relationships, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :pursuer_id, references(:vehicles, type: :uuid), null: false
      add :evader_id, references(:vehicles, type: :uuid), null: false
      add :fight_id, references(:fights, type: :uuid), null: false
      add :position, :string, null: false, default: "far"
      add :active, :boolean, null: false, default: true

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:chase_relationships, [:pursuer_id])
    create index(:chase_relationships, [:evader_id])
    create index(:chase_relationships, [:fight_id])

    # Add check constraints
    create constraint(:chase_relationships, :different_vehicles, check: "pursuer_id <> evader_id")

    create constraint(:chase_relationships, :position_values,
             check: "position IN ('near', 'far')"
           )

    # Unique index for active relationships
    execute """
    CREATE UNIQUE INDEX unique_active_relationship
    ON chase_relationships (pursuer_id, evader_id, fight_id)
    WHERE active = true
    """

    # Effects table
    create table(:effects, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :fight_id, references(:fights, type: :uuid)
      add :user_id, references(:users, type: :uuid)
      add :start_sequence, :integer
      add :end_sequence, :integer
      add :start_shot, :integer
      add :end_shot, :integer
      add :severity, :string
      add :description, :text
      add :name, :string

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:effects, [:fight_id])
    create index(:effects, [:user_id])

    # Fight events table
    create table(:fight_events, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :fight_id, references(:fights, type: :uuid), null: false
      add :event_type, :string
      add :description, :text
      add :details, :jsonb, default: "{}"

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:fight_events, [:fight_id])

    # Image positions table (polymorphic)
    create table(:image_positions, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :positionable_type, :string, null: false
      add :positionable_id, :uuid, null: false
      add :context, :string, null: false
      add :x_position, :float, default: 0.0
      add :y_position, :float, default: 0.0
      add :style_overrides, :jsonb, default: "{}"

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:image_positions, [:positionable_type, :positionable_id])
    create unique_index(:image_positions, [:positionable_type, :positionable_id, :context])

    # Memberships table (party memberships)
    create table(:memberships, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :party_id, references(:parties, type: :uuid), null: false
      add :character_id, references(:characters, type: :uuid)
      add :vehicle_id, references(:vehicles, type: :uuid)

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:memberships, [:party_id])
    create index(:memberships, [:character_id])
    create index(:memberships, [:vehicle_id])
    create unique_index(:memberships, [:party_id, :vehicle_id])

    # Onboarding progresses table
    create table(:onboarding_progresses, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid), null: false
      add :first_campaign_created_at, :naive_datetime_usec
      add :first_character_created_at, :naive_datetime_usec
      add :first_fight_created_at, :naive_datetime_usec
      add :first_faction_created_at, :naive_datetime_usec
      add :first_party_created_at, :naive_datetime_usec
      add :first_site_created_at, :naive_datetime_usec
      add :congratulations_dismissed_at, :naive_datetime_usec
      add :first_campaign_activated_at, :naive_datetime_usec

      timestamps(inserted_at: :created_at, type: :naive_datetime_usec)
    end

    create index(:onboarding_progresses, [:user_id])

    # Active Storage tables (Rails file storage, used for images)
    create table(:active_storage_blobs, primary_key: false) do
      add :id, :serial, primary_key: true
      add :key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string
      add :metadata, :text
      add :service_name, :string, null: false
      add :byte_size, :bigint, null: false
      add :checksum, :string
      add :created_at, :naive_datetime_usec, null: false
    end

    create unique_index(:active_storage_blobs, [:key])

    create table(:active_storage_attachments, primary_key: false) do
      add :id, :serial, primary_key: true
      add :name, :string, null: false
      add :record_type, :string, null: false
      add :record_id, :uuid
      add :blob_id, references(:active_storage_blobs, type: :bigint), null: false
      add :created_at, :naive_datetime_usec, null: false
    end

    create index(:active_storage_attachments, [:blob_id])
    create index(:active_storage_attachments, [:record_type, :name, :record_id])
  end

  defp drop_baseline_schema do
    # Drop tables in reverse order of creation
    drop_if_exists table(:active_storage_attachments)
    drop_if_exists table(:active_storage_blobs)
    drop_if_exists table(:onboarding_progresses)
    drop_if_exists table(:memberships)
    drop_if_exists table(:image_positions)
    drop_if_exists table(:fight_events)
    drop_if_exists table(:effects)

    execute "DROP INDEX IF EXISTS unique_active_relationship"
    drop_if_exists table(:chase_relationships)

    drop_if_exists table(:character_schticks)
    drop_if_exists table(:character_effects)
    drop_if_exists table(:carries)
    drop_if_exists table(:campaign_memberships)
    drop_if_exists table(:attunements)
    drop_if_exists table(:advancements)

    # Remove FK from users before dropping invitations
    alter table(:users) do
      modify :pending_invitation_id, :uuid, from: references(:invitations, type: :uuid)
    end

    drop_if_exists table(:invitations)

    # Remove self-referencing FKs from shots before dropping
    alter table(:shots) do
      modify :driver_id, :uuid, from: references(:shots, type: :uuid)
      modify :driving_id, :uuid, from: references(:shots, type: :uuid)
    end

    drop_if_exists table(:shots)
    drop_if_exists table(:schticks)
    drop_if_exists table(:weapons)
    drop_if_exists table(:parties)
    drop_if_exists table(:sites)
    drop_if_exists table(:fights)
    drop_if_exists table(:vehicles)
    drop_if_exists table(:characters)
    drop_if_exists table(:junctures)
    drop_if_exists table(:factions)

    # Remove FK from users before dropping campaigns
    alter table(:users) do
      modify :current_campaign_id, :uuid, from: references(:campaigns, type: :uuid)
    end

    drop_if_exists table(:campaigns)
    drop_if_exists table(:users)
  end
end
