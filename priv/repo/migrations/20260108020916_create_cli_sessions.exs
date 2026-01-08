defmodule ShotElixir.Repo.Migrations.CreateCliSessions do
  use Ecto.Migration

  def change do
    create table(:cli_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ip_address, :string
      add :user_agent, :string
      add :last_seen_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cli_sessions, [:user_id])
    create index(:cli_sessions, [:inserted_at])
  end
end
