defmodule ShotElixir.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :color, :string
      add :image_url, :string

      add :copied_from_location_id,
          references(:locations, type: :binary_id, on_delete: :nilify_all)

      add :fight_id, references(:fights, type: :binary_id, on_delete: :delete_all)
      add :site_id, references(:sites, type: :binary_id, on_delete: :delete_all)
      timestamps(inserted_at: :created_at)
    end

    # Case-insensitive unique indexes (one location name per fight/site)
    execute(
      "CREATE UNIQUE INDEX locations_fight_name_idx ON locations (fight_id, lower(name)) WHERE fight_id IS NOT NULL",
      "DROP INDEX locations_fight_name_idx"
    )

    execute(
      "CREATE UNIQUE INDEX locations_site_name_idx ON locations (site_id, lower(name)) WHERE site_id IS NOT NULL",
      "DROP INDEX locations_site_name_idx"
    )

    # XOR constraint: exactly one of fight_id or site_id must be set
    create constraint(:locations, :location_scope_check,
             check:
               "(fight_id IS NOT NULL AND site_id IS NULL) OR (fight_id IS NULL AND site_id IS NOT NULL)"
           )
  end
end
