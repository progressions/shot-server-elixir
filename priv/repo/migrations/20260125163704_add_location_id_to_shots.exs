defmodule ShotElixir.Repo.Migrations.AddLocationIdToShots do
  use Ecto.Migration

  def change do
    alter table(:shots) do
      add :location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:shots, [:location_id])
  end
end
