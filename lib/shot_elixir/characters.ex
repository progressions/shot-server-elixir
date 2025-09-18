defmodule ShotElixir.Characters do
  @moduledoc """
  The Characters context for managing Feng Shui 2 characters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character

  @character_types ["PC", "Ally", "Mook", "Featured Foe", "Boss", "Uber-Boss"]

  def list_characters(campaign_id) do
    query = from c in Character,
      where: c.campaign_id == ^campaign_id and c.active == true

    Repo.all(query)
  end

  def get_character!(id), do: Repo.get!(Character, id)
  def get_character(id), do: Repo.get(Character, id)

  def create_character(attrs \\ %{}) do
    %Character{}
    |> Character.changeset(attrs)
    |> Repo.insert()
  end

  def update_character(%Character{} = character, attrs) do
    character
    |> Character.changeset(attrs)
    |> Repo.update()
  end

  def delete_character(%Character{} = character) do
    character
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def duplicate_character(%Character{} = character, new_name) do
    attrs = Map.from_struct(character)
    |> Map.delete(:id)
    |> Map.delete(:__meta__)
    |> Map.put(:name, new_name)

    create_character(attrs)
  end

  defmodule Character do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    @default_action_values %{
      "Guns" => 0,
      "Martial Arts" => 0,
      "Sorcery" => 0,
      "Scroungetech" => 0,
      "Genome" => 0,
      "Mutant" => 0,
      "Creature" => 0,
      "Defense" => 0,
      "Toughness" => 0,
      "Speed" => 0,
      "Fortune" => 0,
      "Max Fortune" => 0,
      "FortuneType" => "Fortune",
      "MainAttack" => "Guns",
      "SecondaryAttack" => nil,
      "Wounds" => 0,
      "Type" => "PC",
      "Marks of Death" => 0,
      "Archetype" => "",
      "Damage" => 0
    }

    @character_types ["PC", "Ally", "Mook", "Featured Foe", "Boss", "Uber-Boss"]

    schema "characters" do
      field :name, :string
      field :archetype, :string
      field :character_type, :string, default: "PC"
      field :active, :boolean, default: true

      # Core attributes
      field :impairments, :integer, default: 0
      field :category, :string
      field :full_name, :string
      field :catchphrase, :string

      # Action values stored as JSON
      field :action_values, :map, default: @default_action_values
      field :description, :map, default: %{}
      field :skills, :map, default: %{}

      # Specific stats
      field :fortune, :integer, default: 0
      field :max_fortune, :integer, default: 0
      field :wounds, :integer, default: 0
      field :marks_of_death, :integer, default: 0
      field :defense, :integer, default: 13
      field :toughness, :integer, default: 5
      field :speed, :integer, default: 5
      field :damage, :integer, default: 7

      # AI-generated content
      field :notion_page_id, :string
      field :driver_id, :string

      belongs_to :user, ShotElixir.Accounts.User
      belongs_to :campaign, ShotElixir.Campaigns.Campaign
      belongs_to :faction, ShotElixir.Factions.Faction
      belongs_to :juncture, ShotElixir.Junctures.Juncture

      has_many :shots, ShotElixir.Fights.Shot
      has_many :fights, through: [:shots, :fight]
      has_many :character_effects, ShotElixir.Effects.CharacterEffect
      has_many :character_schticks, ShotElixir.Schticks.CharacterSchtick
      has_many :schticks, through: [:character_schticks, :schtick]
      has_many :advancements, ShotElixir.Characters.Advancement
      has_many :carries, ShotElixir.Weapons.Carry
      has_many :weapons, through: [:carries, :weapon]
      has_many :memberships, ShotElixir.Parties.Membership
      has_many :parties, through: [:memberships, :party]
      has_many :attunements, ShotElixir.Sites.Attunement
      has_many :sites, through: [:attunements, :site]

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(character, attrs) do
      character
      |> cast(attrs, [:name, :archetype, :character_type, :active, :impairments,
                      :category, :full_name, :catchphrase, :action_values, :description,
                      :skills, :fortune, :max_fortune, :wounds, :marks_of_death,
                      :defense, :toughness, :speed, :damage, :notion_page_id,
                      :driver_id, :user_id, :campaign_id, :faction_id, :juncture_id])
      |> validate_required([:name, :campaign_id])
      |> validate_inclusion(:character_type, @character_types)
      |> validate_number(:impairments, greater_than_or_equal_to: 0)
      |> unique_constraint([:name, :campaign_id])
      |> ensure_default_values()
    end

    defp ensure_default_values(changeset) do
      changeset
      |> put_change_if_nil(:action_values, @default_action_values)
      |> put_change_if_nil(:character_type, "PC")
    end

    defp put_change_if_nil(changeset, key, value) do
      case get_field(changeset, key) do
        nil -> put_change(changeset, key, value)
        _ -> changeset
      end
    end
  end

  defmodule Advancement do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "advancements" do
      field :description, :string
      belongs_to :character, Character

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(advancement, attrs) do
      advancement
      |> cast(attrs, [:description, :character_id])
      |> validate_required([:description, :character_id])
    end
  end
end