defmodule ShotElixir.Adventures.AdventureFight do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "adventure_fights" do
    belongs_to :adventure, ShotElixir.Adventures.Adventure
    belongs_to :fight, ShotElixir.Fights.Fight

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(adventure_fight, attrs) do
    adventure_fight
    |> cast(attrs, [:adventure_id, :fight_id])
    |> validate_required([:adventure_id, :fight_id])
    |> foreign_key_constraint(:adventure_id)
    |> foreign_key_constraint(:fight_id)
    |> unique_constraint([:adventure_id, :fight_id])
  end
end
