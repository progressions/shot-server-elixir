defmodule ShotElixir.Repo.Migrations.AddNotionFieldsToSitesPartiesFactions do
  use Ecto.Migration

  def change do
    # Add Notion sync fields to sites table
    alter table(:sites) do
      add :notion_page_id, :string
      add :last_synced_to_notion_at, :utc_datetime
    end

    create unique_index(:sites, [:notion_page_id], where: "notion_page_id IS NOT NULL")

    # Add Notion sync fields to parties table
    alter table(:parties) do
      add :notion_page_id, :string
      add :last_synced_to_notion_at, :utc_datetime
    end

    create unique_index(:parties, [:notion_page_id], where: "notion_page_id IS NOT NULL")

    # Add Notion sync fields to factions table
    alter table(:factions) do
      add :notion_page_id, :string
      add :last_synced_to_notion_at, :utc_datetime
    end

    create unique_index(:factions, [:notion_page_id], where: "notion_page_id IS NOT NULL")
  end
end
