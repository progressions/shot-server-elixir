defmodule ShotElixir.Repo.Migrations.CreateCliAuthorizationCodes do
  use Ecto.Migration

  def change do
    create table(:cli_authorization_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :approved, :boolean, default: false, null: false
      add :expires_at, :utc_datetime, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cli_authorization_codes, [:code])
    create index(:cli_authorization_codes, [:user_id])
    create index(:cli_authorization_codes, [:expires_at])
  end
end
