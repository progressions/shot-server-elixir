defmodule ShotElixir.Repo.Migrations.AddEntityFieldsToNotionSyncLogs do
  use Ecto.Migration

  def up do
    alter table(:notion_sync_logs) do
      add :entity_type, :string
      add :entity_id, :binary_id
      modify :character_id, :binary_id, null: true
    end

    create index(:notion_sync_logs, [:entity_type, :entity_id])

    # Backfill existing logs - assuming they are all character logs
    execute("UPDATE notion_sync_logs SET entity_type = 'character', entity_id = character_id")

    # Now make fields non-null
    alter table(:notion_sync_logs) do
      modify :entity_type, :string, null: false
      modify :entity_id, :binary_id, null: false
    end
  end

  def down do
    alter table(:notion_sync_logs) do
      remove :entity_type
      remove :entity_id
      modify :character_id, :binary_id, null: false
    end
  end
end
