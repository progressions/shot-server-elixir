defmodule ShotElixir.Fights.Fight do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fights" do
    field :name, :string
    field :active, :boolean, default: true
    field :sequence, :integer, default: 0
    field :archived, :boolean, default: false
    field :description, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :season, :integer
    field :session, :integer
    field :server_id, :integer
    field :channel_id, :integer
    field :fight_message_id, :string

    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    has_many :shots, ShotElixir.Fights.Shot
    has_many :character_effects, ShotElixir.Effects.CharacterEffect

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(fight, attrs) do
    fight
    |> cast(attrs, [:name, :active, :sequence, :archived, :description,
                    :started_at, :ended_at, :season, :session, :server_id,
                    :channel_id, :fight_message_id, :campaign_id])
    |> validate_required([:name, :campaign_id])
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
  end
end