defmodule ShotElixir.Repo.Migrations.AddEquippedWeaponToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :equipped_weapon_id, references(:weapons, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:characters, [:equipped_weapon_id])
  end
end
