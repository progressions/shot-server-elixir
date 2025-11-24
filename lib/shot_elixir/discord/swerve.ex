defmodule ShotElixir.Discord.Swerve do
  @moduledoc """
  Schema for storing swerve dice roll history.
  A swerve consists of positive and negative exploding dice rolls.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "swerves" do
    field :username, :string
    field :positives_sum, :integer
    field :positives_rolls, {:array, :integer}
    field :negatives_sum, :integer
    field :negatives_rolls, {:array, :integer}
    field :total, :integer
    field :boxcars, :boolean
    field :rolled_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(swerve, attrs) do
    swerve
    |> cast(attrs, [
      :username,
      :positives_sum,
      :positives_rolls,
      :negatives_sum,
      :negatives_rolls,
      :total,
      :boxcars,
      :rolled_at
    ])
    |> validate_required([
      :username,
      :positives_sum,
      :positives_rolls,
      :negatives_sum,
      :negatives_rolls,
      :total,
      :boxcars,
      :rolled_at
    ])
  end
end
