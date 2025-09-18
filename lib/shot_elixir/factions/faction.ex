defmodule ShotElixir.Factions.Faction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "factions" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true

    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(faction, attrs) do
    faction
    |> cast(attrs, [:name, :description, :active, :campaign_id])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
  end
end
