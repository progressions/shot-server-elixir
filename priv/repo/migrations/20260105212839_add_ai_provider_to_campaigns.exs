defmodule ShotElixir.Repo.Migrations.AddAiProviderToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :ai_provider, :string
    end
  end
end
