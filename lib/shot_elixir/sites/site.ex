defmodule ShotElixir.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset
  use Arc.Ecto.Schema

  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sites" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :image_url, :string, virtual: true

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction
    belongs_to :juncture, ShotElixir.Junctures.Juncture
    has_many :attunements, ShotElixir.Sites.Attunement

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Site"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :description, :active, :campaign_id, :faction_id, :juncture_id])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:faction_id)
    |> foreign_key_constraint(:juncture_id)
  end

  @doc """
  Returns the image URL for a site, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = site) do
    site.image_url
  end
end
