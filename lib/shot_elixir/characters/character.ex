defmodule ShotElixir.Characters.Character do
  use Ecto.Schema
  import Ecto.Changeset
  use Arc.Ecto.Schema
  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
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

  @default_description %{
    "Nicknames" => "",
    "Age" => "",
    "Height" => "",
    "Weight" => "",
    "Hair Color" => "",
    "Eye Color" => "",
    "Style of Dress" => "",
    "Appearance" => "",
    "Background" => "",
    "Melodramatic Hook" => ""
  }

  @character_types ["PC", "NPC", "Ally", "Mook", "Featured Foe", "Boss", "Uber-Boss"]

  schema "characters" do
    field :name, :string
    field :active, :boolean, default: true
    field :defense, :integer
    field :impairments, :integer, default: 0
    field :color, :string

    # JSONB fields
    field :action_values, :map, default: @default_action_values
    field :description, :map, default: %{}
    field :skills, :map, default: %{}
    field :status, {:array, :string}, default: []

    # Additional fields (image_url is provided virtually via external services)
    field :image_url, :string, virtual: true
    field :task, :boolean
    field :summary, :string
    field :wealth, :string
    field :is_template, :boolean, default: false
    field :notion_page_id, Ecto.UUID
    field :last_synced_to_notion_at, :utc_datetime

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

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Character"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [
      :name,
      :active,
      :defense,
      :impairments,
      :color,
      :action_values,
      :description,
      :skills,
      :status,
      :task,
      :summary,
      :wealth,
      :is_template,
      :notion_page_id,
      :last_synced_to_notion_at,
      :user_id,
      :campaign_id,
      :faction_id,
      :juncture_id
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_number(:impairments, greater_than_or_equal_to: 0)
    |> validate_character_type()
    |> unique_constraint([:name, :campaign_id])
    |> ensure_default_values()
  end

  @doc """
  Returns the image URL for a character, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = character) do
    # Image storage handled by Rails app
    character.image_url
  end

  defp validate_character_type(changeset) do
    action_values = get_field(changeset, :action_values) || %{}
    character_type = Map.get(action_values, "Type", "PC")

    if character_type in @character_types do
      changeset
    else
      add_error(changeset, :action_values, "invalid character type")
    end
  end

  defp ensure_default_values(changeset) do
    changeset
    |> ensure_default_action_values()
    |> ensure_default_description()
  end

  defp ensure_default_action_values(changeset) do
    action_values = get_field(changeset, :action_values) || %{}
    merged_values = Map.merge(@default_action_values, action_values)
    put_change(changeset, :action_values, merged_values)
  end

  defp ensure_default_description(changeset) do
    description = get_field(changeset, :description) || %{}
    merged_description = Map.merge(@default_description, description)
    put_change(changeset, :description, merged_description)
  end

end
