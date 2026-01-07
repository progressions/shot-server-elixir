defmodule ShotElixir.Parties.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Valid roles for party composition slots
  @valid_roles [:boss, :featured_foe, :mook, :ally]

  schema "memberships" do
    belongs_to :party, ShotElixir.Parties.Party
    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :vehicle, ShotElixir.Vehicles.Vehicle

    # Party composition fields
    field :role, Ecto.Enum, values: @valid_roles
    field :default_mook_count, :integer
    field :position, :integer

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @doc """
  Returns the list of valid roles for party composition.
  """
  def valid_roles, do: @valid_roles

  @doc """
  Standard changeset for legacy memberships (no role).
  """
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

  @doc """
  Changeset for composition slots (with role).
  Allows empty slots (no character/vehicle) when role is set.
  """
  def slot_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:party_id, :character_id, :vehicle_id, :role, :default_mook_count, :position])
    |> validate_required([:party_id, :role])
    |> validate_inclusion(:role, @valid_roles)
    |> validate_mook_count()
    |> validate_no_both_character_and_vehicle()
    |> foreign_key_constraint(:party_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:vehicle_id)
  end

  @doc """
  Changeset for updating a slot (populating with character, changing mook count, etc.)
  """
  def update_slot_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:character_id, :vehicle_id, :default_mook_count, :position])
    |> validate_mook_count()
    |> validate_no_both_character_and_vehicle()
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:vehicle_id)
  end

  # For legacy memberships: require either character or vehicle
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

  # For slots: don't require character/vehicle but can't have both
  defp validate_no_both_character_and_vehicle(changeset) do
    character_id = get_change(changeset, :character_id) || changeset.data.character_id
    vehicle_id = get_change(changeset, :vehicle_id) || changeset.data.vehicle_id

    case {character_id, vehicle_id} do
      {_, nil} -> changeset
      {nil, _} -> changeset
      {_, _} -> add_error(changeset, :base, "Cannot have both character_id and vehicle_id")
    end
  end

  # Validate mook count is only set for mook role and is positive
  defp validate_mook_count(changeset) do
    role = get_field(changeset, :role)
    mook_count = get_field(changeset, :default_mook_count)

    cond do
      # Mook count only valid for mook role
      mook_count != nil && role != :mook ->
        add_error(changeset, :default_mook_count, "can only be set for mook role")

      # Mook count must be positive
      mook_count != nil && mook_count < 1 ->
        add_error(changeset, :default_mook_count, "must be at least 1")

      true ->
        changeset
    end
  end
end
