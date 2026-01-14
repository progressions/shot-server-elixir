defmodule ShotElixir.Repo.Migrations.AddNotionOAuthFieldsToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :notion_database_ids, :map, default: "{}"
      add :notion_access_token, :string
      add :notion_bot_id, :string
      add :notion_workspace_name, :string
      add :notion_workspace_icon, :string
      add :notion_owner, :map
    end
  end
end
