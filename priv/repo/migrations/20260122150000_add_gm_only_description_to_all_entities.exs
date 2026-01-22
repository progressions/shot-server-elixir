defmodule ShotElixir.Repo.Migrations.AddGmOnlyDescriptionToAllEntities do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :rich_description_gm_only, :text
    end

    alter table(:parties) do
      add :rich_description_gm_only, :text
    end

    alter table(:factions) do
      add :rich_description_gm_only, :text
    end

    alter table(:junctures) do
      add :rich_description_gm_only, :text
    end

    alter table(:adventures) do
      add :rich_description_gm_only, :text
    end
  end
end
