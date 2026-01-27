defmodule ShotElixir.Repo.Migrations.AddExpiryToCharacterEffects do
  use Ecto.Migration

  def change do
    alter table(:character_effects) do
      add :end_sequence, :integer
      add :end_shot, :integer
    end
  end
end
