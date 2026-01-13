defmodule ShotElixir.Repo.Migrations.AddEntityFieldsToNotionSyncLogs do
  use Ecto.Migration

  def up do
    alter table(:notion_sync_logs) do
      add :entity_type, :string
      add :entity_id, :binary_id
      modify :character_id, :binary_id, null: true
    end

    execute("""
    UPDATE notion_sync_logs
    SET entity_type = 'character', entity_id = character_id
    WHERE entity_type IS NULL
    """)

    execute("ALTER TABLE notion_sync_logs ALTER COLUMN entity_type SET NOT NULL")
    execute("ALTER TABLE notion_sync_logs ALTER COLUMN entity_id SET NOT NULL")

    create index(:notion_sync_logs, [:entity_type, :entity_id])
  end

  def down do
    drop index(:notion_sync_logs, [:entity_type, :entity_id])

    execute("ALTER TABLE notion_sync_logs ALTER COLUMN entity_type DROP NOT NULL")
    execute("ALTER TABLE notion_sync_logs ALTER COLUMN entity_id DROP NOT NULL")

    execute("""
    UPDATE notion_sync_logs
    SET character_id = entity_id
    WHERE entity_type = 'character' AND character_id IS NULL
    """)

    alter table(:notion_sync_logs) do
      modify :character_id, :binary_id, null: false
      remove :entity_type
      remove :entity_id
    end
  end
end
