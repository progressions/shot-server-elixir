# Placeholder modules to avoid compilation errors
# These will be replaced with full implementations in Phase 1

# Factions and Junctures moved to separate files in factions/ and junctures/ directories

# Schticks moved to schticks/ directory

defmodule ShotElixir.Schticks.CharacterSchtick do
  use Ecto.Schema
  @primary_key {:id, :id, autogenerate: true}
  schema "character_schticks" do
    belongs_to :character, ShotElixir.Characters.Character, type: :binary_id
    belongs_to :schtick, ShotElixir.Schticks.Schtick, type: :binary_id
    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end
end

# Moved to weapons/weapon.ex - remove from stubs
# defmodule ShotElixir.Weapons do
#   # Weapon module moved to separate file
# end

defmodule ShotElixir.Weapons.Carry do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "carries" do
    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :weapon, ShotElixir.Weapons.Weapon
    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end
end

# Sites moved to sites/ directory

# Parties moved to parties/ directory
