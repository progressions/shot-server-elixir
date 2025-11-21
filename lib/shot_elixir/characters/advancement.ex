defmodule ShotElixir.Characters.Advancement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "advancements" do
    field :description, :string
    belongs_to :character, ShotElixir.Characters.Character

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(advancement, attrs) do
    advancement
    |> cast(attrs, [:description, :character_id])
    |> validate_required([:character_id])
  end
end
