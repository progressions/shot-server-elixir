defmodule ShotElixir.Repo.Migrations.CreateNotionSyncLogs do
  use Ecto.Migration

  def change do
    create table(:notion_sync_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false
      add :payload, :map, default: %{}
      add :response, :map, default: %{}
      add :error_message, :text

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create index(:notion_sync_logs, [:character_id])
    create index(:notion_sync_logs, [:created_at])
  end
end
