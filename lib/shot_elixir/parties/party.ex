defmodule ShotElixir.Parties.Party do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "parties" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction
    belongs_to :juncture, ShotElixir.Junctures.Juncture
    has_many :memberships, ShotElixir.Parties.Membership
    has_many :characters, through: [:memberships, :character]
    has_many :vehicles, through: [:memberships, :vehicle]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(party, attrs) do
    party
    |> cast(attrs, [:name, :description, :active, :campaign_id, :faction_id, :juncture_id])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:faction_id)
    |> foreign_key_constraint(:juncture_id)
  end
end