defmodule ShotElixir.Repo.Migrations.AddNotionOAuthFieldsToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :notion_database_ids, :map, default: "{}", if_not_exists: true
      add :notion_access_token, :string, if_not_exists: true
      add :notion_workspace_name, :string, if_not_exists: true
    end
  end
end
