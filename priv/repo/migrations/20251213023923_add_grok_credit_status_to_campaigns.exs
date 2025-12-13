defmodule ShotElixir.Repo.Migrations.AddGrokCreditStatusToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :grok_credits_exhausted_at, :utc_datetime
      add :grok_credits_exhausted_notified_at, :utc_datetime
    end
  end
end
