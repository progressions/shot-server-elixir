defmodule ShotElixir.Repo.Migrations.RemoveLegacyGrokColumns do
  use Ecto.Migration

  def up do
    # Add provider-agnostic notification timestamp for rate limiting
    alter table(:campaigns) do
      add :ai_credits_exhausted_notified_at, :utc_datetime
    end

    # Copy existing notification timestamps to new column
    execute """
    UPDATE campaigns
    SET ai_credits_exhausted_notified_at = grok_credits_exhausted_notified_at
    WHERE grok_credits_exhausted_notified_at IS NOT NULL
    """

    # Drop legacy grok-specific columns
    alter table(:campaigns) do
      remove :grok_credits_exhausted_at
      remove :grok_credits_exhausted_notified_at
    end
  end

  def down do
    # Restore legacy columns
    alter table(:campaigns) do
      add :grok_credits_exhausted_at, :utc_datetime
      add :grok_credits_exhausted_notified_at, :utc_datetime
    end

    # Copy data back
    execute """
    UPDATE campaigns
    SET grok_credits_exhausted_notified_at = ai_credits_exhausted_notified_at
    WHERE ai_credits_exhausted_notified_at IS NOT NULL
    """

    # Remove new column
    alter table(:campaigns) do
      remove :ai_credits_exhausted_notified_at
    end
  end
end
