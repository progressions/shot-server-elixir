defmodule ShotElixir.Repo.Migrations.AddCurrentCharacterIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :current_character_id, references(:characters, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:users, [:current_character_id])
  end
end
