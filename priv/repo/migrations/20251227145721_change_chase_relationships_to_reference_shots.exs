defmodule ShotElixir.Repo.Migrations.ChangeChaseRelationshipsToReferenceShots do
  use Ecto.Migration

  def up do
    # Drop the check constraint that prevents same vehicle chasing itself
    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS different_vehicles"

    # Drop any existing foreign key constraints (using IF EXISTS for idempotency)
    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS chase_relationships_pursuer_id_fkey"

    execute "ALTER TABLE chase_relationships DROP CONSTRAINT IF EXISTS chase_relationships_evader_id_fkey"

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
