defmodule ShotElixir.Repo.Migrations.AddGmOnlyDescriptionToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :rich_description_gm_only, :text
    end
  end
end
