defmodule ShotElixir.Repo.Migrations.CreateAiCredentials do
  use Ecto.Migration

  def change do
    create table(:ai_credentials, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :api_key_encrypted, :binary
      add :access_token_encrypted, :binary
      add :refresh_token_encrypted, :binary
      add :token_expires_at, :utc_datetime

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create unique_index(:ai_credentials, [:user_id, :provider])
    create index(:ai_credentials, [:user_id])
  end
end
