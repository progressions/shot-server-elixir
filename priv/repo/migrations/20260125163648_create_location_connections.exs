defmodule ShotElixir.Repo.Migrations.CreateLocationConnections do
  use Ecto.Migration

  def change do
    create table(:location_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :from_location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :to_location_id, references(:locations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :bidirectional, :boolean, default: true
      add :label, :string
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: :updated_at)
    end

    create index(:location_connections, [:from_location_id])
    create index(:location_connections, [:to_location_id])
  end
end
