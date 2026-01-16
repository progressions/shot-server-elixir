defmodule ShotElixir.Repo.Migrations.AddNotionStatusToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :notion_status, :string
    end

    # Set initial status based on existing data:
    # - "working" if notion_access_token is present
    # - "disconnected" if not
    execute(
      """
      UPDATE campaigns
      SET notion_status = CASE
        WHEN notion_access_token IS NOT NULL THEN 'working'
        ELSE 'disconnected'
      END
      """,
      "UPDATE campaigns SET notion_status = NULL"
    )
  end
end
