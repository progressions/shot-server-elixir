defmodule ShotElixir.Repo.Migrations.CreateAdventureFights do
  use Ecto.Migration

  def change do
    create table(:adventure_fights, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :adventure_id, references(:adventures, type: :binary_id, on_delete: :delete_all),
        null: false

      add :fight_id, references(:fights, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create index(:adventure_fights, [:adventure_id])
    create index(:adventure_fights, [:fight_id])
    create unique_index(:adventure_fights, [:adventure_id, :fight_id])
  end
end
