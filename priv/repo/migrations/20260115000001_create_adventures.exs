defmodule ShotElixir.Repo.Migrations.CreateAdventures do
  use Ecto.Migration

  def change do
    create table(:adventures, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :season, :integer
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :active, :boolean, default: true, null: false
      add :at_a_glance, :boolean, default: false, null: false
      add :notion_page_id, :string
      add :last_synced_to_notion_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id), null: false
      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    create index(:adventures, [:campaign_id])
    create index(:adventures, [:user_id])
    create index(:adventures, [:active])
    create index(:adventures, [:at_a_glance])
    create unique_index(:adventures, [:notion_page_id], where: "notion_page_id IS NOT NULL")
  end
end
