defmodule ShotElixir.Schticks.Schtick do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "schticks" do
    field :name, :string
    field :description, :string
    field :category, :string
    field :path, :string
    field :color, :string
    field :image_url, :string, virtual: true
    field :bonus, :boolean, default: false
    field :archetypes, {:array, :string}
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :prerequisite, __MODULE__

    # Self-referential relationship for prerequisites
    has_many :dependent_schticks, __MODULE__, foreign_key: :prerequisite_id

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(schtick, attrs) do
    schtick
    |> cast(attrs, [
      :name,
      :description,
      :category,
      :path,
      :color,
      :bonus,
      :archetypes,
      :active,
      :at_a_glance,
      :campaign_id,
      :prerequisite_id
    ])
    |> validate_required([:name, :campaign_id])
    |> foreign_key_constraint(:prerequisite_id)
    |> unique_constraint([:category, :name, :campaign_id],
      name: :index_schticks_on_category_name_and_campaign
    )
  end

  @doc """
  Standard categories used in Feng Shui 2.
  Note: The database accepts any category string (like Rails), so this is
  informational only. Categories are typically titleized (e.g., "Guns", "Martial Arts").
  """
  def categories do
    [
      "Guns",
      "Martial Arts",
      "Driving",
      "Sorcery",
      "Creature",
      "Transformed Animal",
      "Gene Freak",
      "Cyborg",
      "Foe"
    ]
  end

  @doc """
  Standard paths used in Feng Shui 2.
  Note: The database accepts any path string. "Core" is a special path that
  applies to all archetypes.
  """
  def paths do
    [
      "Core",
      "Path of the Warrior",
      "Path of the Bandit",
      "Path of the Driver",
      "Path of the Cop",
      "Path of the Sword",
      "Path of the Gun",
      "Path of the Shield",
      "Path of the Dragon",
      "Path of the Tiger",
      "Path of the Phoenix",
      "Path of the Ninja",
      "Path of the Samurai"
    ]
  end
end
