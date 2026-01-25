defmodule ShotElixir.Fights.LocationConnection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "location_connections" do
    field :bidirectional, :boolean, default: true
    field :label, :string

    belongs_to :from_location, ShotElixir.Fights.Location
    belongs_to :to_location, ShotElixir.Fights.Location

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:from_location_id, :to_location_id, :bidirectional, :label])
    |> validate_required([:from_location_id, :to_location_id])
    |> foreign_key_constraint(:from_location_id)
    |> foreign_key_constraint(:to_location_id)
  end
end
