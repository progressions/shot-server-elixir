defmodule ShotElixir.Repo.Migrations.CreateAdventureVillains do
  use Ecto.Migration

  def change do
    create table(:adventure_villains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :adventure_id, references(:adventures, type: :binary_id, on_delete: :delete_all), null: false
      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create index(:adventure_villains, [:adventure_id])
    create index(:adventure_villains, [:character_id])
    create unique_index(:adventure_villains, [:adventure_id, :character_id])
  end
end
