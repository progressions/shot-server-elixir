defmodule ShotElixir.Repo.Migrations.AddProviderAgnosticCreditExhaustion do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :ai_credits_exhausted_at, :utc_datetime
      add :ai_credits_exhausted_provider, :string
    end

    # Copy existing Grok credit exhaustion data to new fields
    execute(
      """
      UPDATE campaigns
      SET ai_credits_exhausted_at = grok_credits_exhausted_at,
          ai_credits_exhausted_provider = 'grok'
      WHERE grok_credits_exhausted_at IS NOT NULL
      """,
      """
      UPDATE campaigns
      SET ai_credits_exhausted_at = NULL,
          ai_credits_exhausted_provider = NULL
      """
    )
  end
end
