defmodule ShotElixir.Repo.Migrations.AddSchtickStateToShots do
  use Ecto.Migration

  def change do
    alter table(:shots) do
      add :schtick_state, :map, null: false, default: %{}
    end
  end
end
