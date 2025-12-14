defmodule ShotElixir.Repo.Migrations.AddAiGenerationEnabledToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :ai_generation_enabled, :boolean, default: true, null: false
    end
  end
end
