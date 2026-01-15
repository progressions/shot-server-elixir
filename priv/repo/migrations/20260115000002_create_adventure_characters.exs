defmodule ShotElixir.Repo.Migrations.CreateAdventureCharacters do
  use Ecto.Migration

  def change do
    create table(:adventure_characters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :adventure_id, references(:adventures, type: :binary_id, on_delete: :delete_all), null: false
      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create index(:adventure_characters, [:adventure_id])
    create index(:adventure_characters, [:character_id])
    create unique_index(:adventure_characters, [:adventure_id, :character_id])
  end
end
