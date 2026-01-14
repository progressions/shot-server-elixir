defmodule ShotElixir.Repo.Migrations.AddAtAGlanceToFights do
  use Ecto.Migration

  def change do
    # Use IF NOT EXISTS to handle cases where structure.sql already has the column
    execute(
      "ALTER TABLE fights ADD COLUMN IF NOT EXISTS at_a_glance BOOLEAN NOT NULL DEFAULT false",
      "ALTER TABLE fights DROP COLUMN IF EXISTS at_a_glance"
    )
  end
end
