defmodule ShotElixir.Fights.Shot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shots" do
    field :shot, :integer
    field :position, :string
    field :count, :integer, default: 0
    field :color, :string
    field :impairments, :integer, default: 0
    field :location, :string
    field :was_rammed_or_damaged, :boolean, default: false

    belongs_to :fight, ShotElixir.Fights.Fight
    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :vehicle, ShotElixir.Vehicles.Vehicle
    belongs_to :driver, ShotElixir.Characters.Character
    belongs_to :driving, ShotElixir.Vehicles.Vehicle

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(shot, attrs) do
    shot
    |> cast(attrs, [
      :shot,
      :position,
      :count,
      :color,
      :impairments,
      :location,
      :was_rammed_or_damaged,
      :fight_id,
      :character_id,
      :vehicle_id,
      :driver_id,
      :driving_id
    ])
    |> validate_required([:shot, :fight_id])
    |> validate_number(:shot, greater_than_or_equal_to: 0)
    |> validate_number(:count, greater_than_or_equal_to: 0)
    |> validate_number(:impairments, greater_than_or_equal_to: 0)
    |> validate_actor_presence()
  end

  defp validate_actor_presence(changeset) do
    character_id = get_field(changeset, :character_id)
    vehicle_id = get_field(changeset, :vehicle_id)

    cond do
      character_id == nil and vehicle_id == nil ->
        add_error(changeset, :base, "must have either character or vehicle")

      character_id != nil and vehicle_id != nil ->
        add_error(changeset, :base, "cannot have both character and vehicle")

      true ->
        changeset
    end
  end
end
