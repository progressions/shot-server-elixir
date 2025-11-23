defmodule ShotElixir.Fights.FightEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fight_events" do
    field :event_type, :string
    field :description, :string
    field :details, :map, default: %{}

    belongs_to :fight, ShotElixir.Fights.Fight

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(fight_event, attrs) do
    fight_event
    |> cast(attrs, [:event_type, :description, :details, :fight_id])
    |> validate_required([:event_type, :fight_id])
  end
end
