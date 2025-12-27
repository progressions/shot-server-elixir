defmodule ShotElixir.Chases.ChaseRelationship do
  @moduledoc """
  Represents a chase relationship between two vehicle instances (shots) in a fight.

  Note: pursuer_id and evader_id reference shots (vehicle instances in a fight),
  not the vehicle templates. This allows multiple instances of the same vehicle
  template to participate in different chase relationships.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chase_relationships" do
    field :position, :string, default: "far"
    field :active, :boolean, default: true

    belongs_to :fight, ShotElixir.Fights.Fight
    # These reference shots (vehicle instances), not vehicles (templates)
    belongs_to :pursuer, ShotElixir.Fights.Shot
    belongs_to :evader, ShotElixir.Fights.Shot

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
    |> check_constraint(:pursuer_id,
      name: :different_shots,
      message: "pursuer and evader cannot be the same"
    )
  end

  def update_changeset(chase_relationship, attrs) do
    chase_relationship
    |> cast(attrs, [:position, :active])
    |> validate_inclusion(:position, ["near", "far"])
  end
end
