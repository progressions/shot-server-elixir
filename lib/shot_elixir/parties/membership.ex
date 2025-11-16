defmodule ShotElixir.Parties.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    belongs_to :party, ShotElixir.Parties.Party
    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :vehicle, ShotElixir.Vehicles.Vehicle

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:party_id, :character_id, :vehicle_id])
    |> validate_required([:party_id])
    |> validate_either_character_or_vehicle()
    |> foreign_key_constraint(:party_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:vehicle_id)

    # Note: Unique constraints were removed in Rails migration 20250928172151
    # The database now allows duplicate memberships
  end

  defp validate_either_character_or_vehicle(changeset) do
    character_id = get_change(changeset, :character_id) || changeset.data.character_id
    vehicle_id = get_change(changeset, :vehicle_id) || changeset.data.vehicle_id

    case {character_id, vehicle_id} do
      {nil, nil} ->
        add_error(changeset, :base, "Either character_id or vehicle_id must be present")

      {_, nil} ->
        changeset

      {nil, _} ->
        changeset

      {_, _} ->
        add_error(changeset, :base, "Cannot have both character_id and vehicle_id")
    end
  end
end
