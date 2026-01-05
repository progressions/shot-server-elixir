defmodule ShotElixir.Repo.Migrations.AddStatusToAiCredentials do
  use Ecto.Migration

  def change do
    alter table(:ai_credentials) do
      # Status: active, suspended (billing issue), invalid (auth failed)
      add :status, :string, default: "active", null: false
      # Optional message explaining the status (e.g., "Billing hard limit reached")
      add :status_message, :string
      # When the status was last updated
      add :status_updated_at, :utc_datetime
    end

    create index(:ai_credentials, [:status])
  end
end
