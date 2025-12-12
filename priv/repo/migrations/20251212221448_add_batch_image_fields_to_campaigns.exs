defmodule ShotElixir.Repo.Migrations.AddBatchImageFieldsToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :batch_image_status, :string
      add :batch_images_total, :integer, default: 0
      add :batch_images_completed, :integer, default: 0
    end
  end
end
