defmodule ShotElixir.Repo.Migrations.AddAtAGlanceToFights do
  use Ecto.Migration

  def change do
    alter table(:fights) do
      add :at_a_glance, :boolean, default: false, null: false, if_not_exists: true
    end
  end
end
