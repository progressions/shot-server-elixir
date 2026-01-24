defmodule ShotElixir.Repo.Migrations.AddNotionImageMappings do
  use Ecto.Migration

  def change do
    create table(:notion_image_mappings, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :notion_page_id, :string, null: false
      add :notion_block_id, :string, null: false
      add :imagekit_file_id, :string, null: false
      add :imagekit_url, :string, null: false
      add :imagekit_file_path, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notion_image_mappings, [:notion_page_id, :notion_block_id],
             name: :notion_image_mappings_page_block_index
           )

    create index(:notion_image_mappings, [:notion_page_id])
  end
end
