defmodule ShotElixir.Vehicles.Vehicle do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vehicles" do
    field :name, :string
    field :frame, :string
    field :image_url, :string
    field :active, :boolean, default: true

    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(vehicle, attrs) do
    vehicle
    |> cast(attrs, [:name, :frame, :image_url, :active, :campaign_id])
    |> validate_required([:name, :campaign_id])
  end
end