defmodule ShotElixir.Repo.Migrations.RemoveLegacyLocationStringFromShots do
  @moduledoc """
  Removes the deprecated location string column from shots table.

  This is Phase 8 of the Location model migration. The location_id foreign key
  now points to the locations table and all code has been updated to use the
  Location model instead of the legacy string field.
  """
  use Ecto.Migration

  def up do
    alter table(:shots) do
      remove :location
    end
  end

  def down do
    alter table(:shots) do
      add :location, :string
    end
  end
end
