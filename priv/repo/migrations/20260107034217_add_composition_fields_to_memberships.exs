defmodule ShotElixir.Repo.Migrations.AddCompositionFieldsToMemberships do
  use Ecto.Migration

  def change do
    alter table(:memberships) do
      # Role for party composition slots: boss, featured_foe, mook, ally
      # nil for legacy memberships without explicit roles
      add :role, :string

      # Default mook count for mook slots (e.g., "12 zombies")
      # Only relevant when role is "mook"
      add :default_mook_count, :integer

      # Position for ordering slots within a party
      add :position, :integer
    end

    # Index for efficient querying by role within a party
    create index(:memberships, [:party_id, :role])

    # Index for ordering slots by position
    create index(:memberships, [:party_id, :position])
  end
end
