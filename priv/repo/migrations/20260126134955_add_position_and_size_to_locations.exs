defmodule ShotElixir.Repo.Migrations.AddPositionAndSizeToLocations do
  use Ecto.Migration

  def change do
    alter table(:locations) do
      add :position_x, :integer, default: 0
      add :position_y, :integer, default: 0
      add :width, :integer, default: 200
      add :height, :integer, default: 150
    end
  end
end
