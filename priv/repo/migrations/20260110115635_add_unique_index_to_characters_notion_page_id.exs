defmodule ShotElixir.Repo.Migrations.AddUniqueIndexToCharactersNotionPageId do
  use Ecto.Migration

  def up do
    execute("""
    WITH ranked AS (
      SELECT id,
             notion_page_id,
             ROW_NUMBER() OVER (
               PARTITION BY notion_page_id
               ORDER BY last_synced_to_notion_at DESC NULLS LAST,
                        updated_at DESC NULLS LAST,
                        created_at DESC NULLS LAST,
                        id
             ) AS row_number
      FROM characters
      WHERE notion_page_id IS NOT NULL
    )
    UPDATE characters
    SET notion_page_id = NULL
    FROM ranked
    WHERE characters.id = ranked.id
      AND ranked.row_number > 1
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS characters_notion_page_id_index
    ON characters (notion_page_id)
    WHERE notion_page_id IS NOT NULL
    """)
  end

  def down do
    drop_if_exists index(:characters, [:notion_page_id], name: :characters_notion_page_id_index)
  end
end
