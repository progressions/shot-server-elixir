defmodule ShotElixir.Adventures.AdventureCharacter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "adventure_characters" do
    belongs_to :adventure, ShotElixir.Adventures.Adventure
    belongs_to :character, ShotElixir.Characters.Character

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(adventure_character, attrs) do
    adventure_character
    |> cast(attrs, [:adventure_id, :character_id])
    |> validate_required([:adventure_id, :character_id])
    |> foreign_key_constraint(:adventure_id)
    |> foreign_key_constraint(:character_id)
    |> unique_constraint([:adventure_id, :character_id])
  end
end
