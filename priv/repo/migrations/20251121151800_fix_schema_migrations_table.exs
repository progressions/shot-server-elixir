defmodule ShotElixir.Repo.Migrations.FixSchemaMigrationsTable do
  use Ecto.Migration

  def up do
    # Add inserted_at column to schema_migrations if it doesn't exist
    # This is needed because Rails schema_migrations only has 'version' column
    # but Ecto expects both 'version' and 'inserted_at'
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'schema_migrations'
        AND column_name = 'inserted_at'
      ) THEN
        ALTER TABLE schema_migrations
        ADD COLUMN inserted_at timestamp(0) NOT NULL DEFAULT NOW();
      END IF;
    END$$;
    """
  end

  def down do
    # Only drop if it exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'schema_migrations'
        AND column_name = 'inserted_at'
      ) THEN
        ALTER TABLE schema_migrations DROP COLUMN inserted_at;
      END IF;
    END$$;
    """
  end
end
