defmodule ShotElixir.Repo.Migrations.CreatePlayerViewTokens do
  use Ecto.Migration

  def change do
    create table(:player_view_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used, :boolean, default: false, null: false
      add :used_at, :utc_datetime

      add :fight_id, references(:fights, type: :binary_id, on_delete: :delete_all), null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create unique_index(:player_view_tokens, [:token])
    create index(:player_view_tokens, [:fight_id])
    create index(:player_view_tokens, [:character_id])
    create index(:player_view_tokens, [:user_id])
    create index(:player_view_tokens, [:expires_at])
  end
end
