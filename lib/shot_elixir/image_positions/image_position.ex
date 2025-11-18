defmodule ShotElixir.ImagePositions.ImagePosition do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "image_positions" do
    field :positionable_type, :string
    field :positionable_id, Ecto.UUID
    field :context, :string
    field :x_position, :float, default: 0.0
    field :y_position, :float, default: 0.0
    field :style_overrides, :map, default: %{}

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(image_position, attrs) do
    image_position
    |> cast(attrs, [
      :positionable_type,
      :positionable_id,
      :context,
      :x_position,
      :y_position,
      :style_overrides
    ])
    |> validate_required([:positionable_type, :positionable_id, :context])
  end
end
