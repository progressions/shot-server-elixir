defmodule ShotElixir.Repo.Migrations.AddSoloFieldsToFights do
  use Ecto.Migration

  def change do
    alter table(:fights) do
      add :solo_mode, :boolean, default: false, null: false
      add :solo_player_character_ids, {:array, :uuid}, default: []
      add :solo_behavior_type, :string, default: "simple"
    end
  end
end
