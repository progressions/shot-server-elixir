defmodule ShotElixir.Chases.ChaseRelationship do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chase_relationships" do
    field :position, :string, default: "far"
    field :active, :boolean, default: true

    belongs_to :fight, ShotElixir.Fights.Fight
    belongs_to :pursuer, ShotElixir.Vehicles.Vehicle
    belongs_to :evader, ShotElixir.Vehicles.Vehicle

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(chase_relationship, attrs) do
    chase_relationship
    |> cast(attrs, [:position, :active, :fight_id, :pursuer_id, :evader_id])
    |> validate_required([:fight_id, :pursuer_id, :evader_id])
    |> validate_inclusion(:position, ["near", "far"])
    |> unique_constraint(
      [
        :pursuer_id,
        :evader_id,
        :fight_id
      ],
      name: :unique_active_relationship
    )
  end

  def update_changeset(chase_relationship, attrs) do
    chase_relationship
    |> cast(attrs, [:position, :active])
    |> validate_inclusion(:position, ["near", "far"])
  end
end
