defmodule ShotElixir.Repo.Migrations.AddSeedingStatusToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      # Status values: nil (not started), "schticks", "weapons", "factions",
      # "junctures", "characters", "prerequisites", "images", "complete"
      add :seeding_status, :string, null: true

      # Track image copying progress
      add :seeding_images_total, :integer, default: 0
      add :seeding_images_completed, :integer, default: 0
    end
  end
end
