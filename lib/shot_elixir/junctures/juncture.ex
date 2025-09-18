defmodule ShotElixir.Junctures.Juncture do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "junctures" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :notion_page_id, :binary_id

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(juncture, attrs) do
    juncture
    |> cast(attrs, [:name, :description, :active, :notion_page_id, :campaign_id, :faction_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
