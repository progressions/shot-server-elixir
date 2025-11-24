defmodule ShotElixir.Effects.Effect do
  @moduledoc """
  Fight-level effects that apply to the entire fight for a duration.
  These are different from CharacterEffect which apply to individual characters.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "effects" do
    field :name, :string
    field :description, :string
    field :severity, :string
    field :start_sequence, :integer
    field :end_sequence, :integer
    field :start_shot, :integer
    field :end_shot, :integer

    belongs_to :fight, ShotElixir.Fights.Fight
    belongs_to :user, ShotElixir.Accounts.User

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @valid_severities ~w(error info success warning)

  def changeset(effect, attrs) do
    effect
    |> cast(attrs, [
      :name,
      :description,
      :severity,
      :start_sequence,
      :end_sequence,
      :start_shot,
      :end_shot,
      :fight_id,
      :user_id
    ])
    |> validate_required([:severity, :fight_id])
    |> validate_inclusion(:severity, @valid_severities)
  end
end
