# Placeholder modules to avoid compilation errors
# These will be replaced with full implementations in Phase 1

# Factions and Junctures moved to separate files in factions/ and junctures/ directories

# Schticks moved to schticks/ directory

defmodule ShotElixir.Schticks.CharacterSchtick do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "character_schticks" do
    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :schtick, ShotElixir.Schticks.Schtick
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

defmodule ShotElixir.Sites do
  defmodule Site do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "sites" do
      field :name, :string
      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end

  defmodule Attunement do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "attunements" do
      belongs_to :character, ShotElixir.Characters.Character
      belongs_to :site, Site
      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end

defmodule ShotElixir.Parties do
  defmodule Party do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "parties" do
      field :name, :string
      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end

  defmodule Membership do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "memberships" do
      belongs_to :party, Party
      belongs_to :character, ShotElixir.Characters.Character
      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end

defmodule ShotElixir.Effects do
  defmodule CharacterEffect do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "character_effects" do
      field :description, :string
      belongs_to :character, ShotElixir.Characters.Character
      belongs_to :fight, ShotElixir.Fights.Fight
      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end