defmodule ShotElixir.Repo.Migrations.AddAtAGlanceToEntities do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:characters) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:vehicles) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:sites) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:factions) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:junctures) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:schticks) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:weapons) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:users) do
      add :at_a_glance, :boolean, default: false, null: false
    end

    alter table(:parties) do
      add :at_a_glance, :boolean, default: false, null: false
    end
  end
end
