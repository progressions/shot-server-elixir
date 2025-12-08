defmodule ShotElixir.Repo.Migrations.CreateWebauthnTables do
  use Ecto.Migration

  def change do
    # Table for storing registered passkey credentials
    create table(:webauthn_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :sign_count, :bigint, default: 0, null: false
      add :transports, {:array, :string}, default: []
      add :backed_up, :boolean, default: false
      add :backup_eligible, :boolean, default: false
      add :attestation_type, :string
      add :name, :string, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webauthn_credentials, [:credential_id])
    create index(:webauthn_credentials, [:user_id])

    # Table for temporary challenge storage during registration/authentication
    create table(:webauthn_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :challenge, :binary, null: false
      add :challenge_type, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:webauthn_challenges, [:user_id])
    create index(:webauthn_challenges, [:expires_at])
  end
end
