defmodule ShotElixir.Effects.CharacterEffect do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "character_effects" do
    field :name, :string
    field :description, :string
    field :severity, :string
    field :action_value, :string
    field :change, :string

    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :vehicle, ShotElixir.Vehicles.Vehicle
    belongs_to :shot, ShotElixir.Fights.Shot

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(effect, attrs) do
    effect
    |> cast(attrs, [
      :name,
      :description,
      :severity,
      :action_value,
      :change,
      :character_id,
      :vehicle_id,
      :shot_id
    ])
    |> validate_required([:name, :shot_id])
    |> validate_at_least_one_present([:character_id, :vehicle_id])
  end

  defp validate_at_least_one_present(changeset, fields) do
    present? =
      Enum.any?(fields, fn field ->
        value = get_field(changeset, field)
        not is_nil(value)
      end)

    if present? do
      changeset
    else
      add_error(
        changeset,
        hd(fields),
        "at least one of #{Enum.join(fields, ", ")} must be present"
      )
    end
  end
