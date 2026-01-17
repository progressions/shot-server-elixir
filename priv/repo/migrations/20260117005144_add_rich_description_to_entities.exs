defmodule ShotElixir.Repo.Migrations.AddRichDescriptionToEntities do
  use Ecto.Migration

  def change do
    # Add rich_description (markdown content from Notion) and mentions (resolved entity references)
    # to all Notion-synced entities
    #
    # Using IF NOT EXISTS to be idempotent (columns may exist from previous attempt)

    # Characters
    execute(
      "ALTER TABLE characters ADD COLUMN IF NOT EXISTS rich_description TEXT",
      "ALTER TABLE characters DROP COLUMN IF EXISTS rich_description"
    )

    execute(
      "ALTER TABLE characters ADD COLUMN IF NOT EXISTS mentions JSONB DEFAULT '{}'::jsonb",
      "ALTER TABLE characters DROP COLUMN IF EXISTS mentions"
    )

    # Sites
    execute(
      "ALTER TABLE sites ADD COLUMN IF NOT EXISTS rich_description TEXT",
      "ALTER TABLE sites DROP COLUMN IF EXISTS rich_description"
    )

    execute(
      "ALTER TABLE sites ADD COLUMN IF NOT EXISTS mentions JSONB DEFAULT '{}'::jsonb",
      "ALTER TABLE sites DROP COLUMN IF EXISTS mentions"
    )

    # Parties
    execute(
      "ALTER TABLE parties ADD COLUMN IF NOT EXISTS rich_description TEXT",
      "ALTER TABLE parties DROP COLUMN IF EXISTS rich_description"
    )

    execute(
      "ALTER TABLE parties ADD COLUMN IF NOT EXISTS mentions JSONB DEFAULT '{}'::jsonb",
      "ALTER TABLE parties DROP COLUMN IF EXISTS mentions"
    )

    # Factions
    execute(
      "ALTER TABLE factions ADD COLUMN IF NOT EXISTS rich_description TEXT",
      "ALTER TABLE factions DROP COLUMN IF EXISTS rich_description"
    )

    execute(
      "ALTER TABLE factions ADD COLUMN IF NOT EXISTS mentions JSONB DEFAULT '{}'::jsonb",
      "ALTER TABLE factions DROP COLUMN IF EXISTS mentions"
    )

    # Junctures
    execute(
      "ALTER TABLE junctures ADD COLUMN IF NOT EXISTS rich_description TEXT",
      "ALTER TABLE junctures DROP COLUMN IF EXISTS rich_description"
    )

    execute(
      "ALTER TABLE junctures ADD COLUMN IF NOT EXISTS mentions JSONB DEFAULT '{}'::jsonb",
      "ALTER TABLE junctures DROP COLUMN IF EXISTS mentions"
    )

    # Adventures
    execute(
      "ALTER TABLE adventures ADD COLUMN IF NOT EXISTS rich_description TEXT",
      "ALTER TABLE adventures DROP COLUMN IF EXISTS rich_description"
    )

    execute(
      "ALTER TABLE adventures ADD COLUMN IF NOT EXISTS mentions JSONB DEFAULT '{}'::jsonb",
      "ALTER TABLE adventures DROP COLUMN IF EXISTS mentions"
    )
  end
end
