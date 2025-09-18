defmodule ShotElixir.Fights.ShotDriver do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shot_drivers" do
    belongs_to :shot, ShotElixir.Fights.Shot
    belongs_to :character, ShotElixir.Characters.Character

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(shot_driver, attrs) do
    shot_driver
    |> cast(attrs, [:shot_id, :character_id])
    |> validate_required([:shot_id, :character_id])
    |> unique_constraint([:shot_id, :character_id])
  end
end