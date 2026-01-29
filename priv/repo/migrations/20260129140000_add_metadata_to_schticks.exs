defmodule ShotElixir.Repo.Migrations.AddMetadataToSchticks do
  use Ecto.Migration

  def change do
    alter table(:schticks) do
      add :metadata, :map, null: false, default: %{}
    end
  end
end
