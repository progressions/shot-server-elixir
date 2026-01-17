defmodule ShotElixir.Repo.Migrations.AddNotionFailureTrackingToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :notion_failure_count, :integer, default: 0
      add :notion_failure_window_start, :utc_datetime
    end
  end
end
