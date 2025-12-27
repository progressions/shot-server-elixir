defmodule ShotElixir.Repo.Migrations.ChangeChaseRelationshipsToReferenceShots do
  use Ecto.Migration

  def up do
    # Delete all existing chase relationships since they contain vehicle template IDs
    # which will violate the new foreign key constraints pointing to shots table
    # Chase relationships are ephemeral and recreated during gameplay
    execute "DELETE FROM chase_relationships"

    # Drop the check constraint that prevents same vehicle chasing itself
    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS different_vehicles"

    # Drop any existing foreign key constraints (using IF EXISTS for idempotency)
    # Include both Rails-generated names and Ecto-style names
    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS chase_relationships_pursuer_id_fkey"

    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS chase_relationships_evader_id_fkey"

    # Rails-generated constraint names (from original Rails schema)
    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS fk_rails_c50d4f4bde"

    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS fk_rails_5a7e7d9f8c"

    # Add new foreign key constraints that reference shots instead of vehicles
    execute """
    ALTER TABLE chase_relationships
    ADD CONSTRAINT chase_relationships_pursuer_id_fkey
    FOREIGN KEY (pursuer_id) REFERENCES shots(id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE chase_relationships
    ADD CONSTRAINT chase_relationships_evader_id_fkey
    FOREIGN KEY (evader_id) REFERENCES shots(id) ON DELETE CASCADE
    """

    # Add new check constraint to prevent same shot chasing itself
    execute """
    ALTER TABLE chase_relationships
    ADD CONSTRAINT different_shots CHECK (pursuer_id <> evader_id)
    """
  end

  def down do
    # Drop the new constraints
    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS different_shots"

    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS chase_relationships_pursuer_id_fkey"

    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS chase_relationships_evader_id_fkey"

    # Restore original foreign keys to vehicles
    execute """
    ALTER TABLE chase_relationships
    ADD CONSTRAINT chase_relationships_pursuer_id_fkey
    FOREIGN KEY (pursuer_id) REFERENCES vehicles(id)
    """

    execute """
    ALTER TABLE chase_relationships
    ADD CONSTRAINT chase_relationships_evader_id_fkey
    FOREIGN KEY (evader_id) REFERENCES vehicles(id)
    """

    # Restore original check constraint
    execute """
    ALTER TABLE chase_relationships
    ADD CONSTRAINT different_vehicles CHECK (pursuer_id <> evader_id)
    """
  end
end
