defmodule ShotElixir.Repo.Migrations.AddOnDeleteToCharacterEffects do
  use Ecto.Migration

  def up do
    drop constraint(:character_effects, "fk_rails_1163db7ee4")

    alter table(:character_effects) do
      modify :shot_id, references(:shots, type: :uuid, on_delete: :delete_all)
    end
  end

  def down do
    drop constraint(:character_effects, "character_effects_shot_id_fkey")

    alter table(:character_effects) do
      modify :shot_id, references(:shots, type: :uuid, on_delete: :nothing),
        name: "fk_rails_1163db7ee4"
    end
  end
end
