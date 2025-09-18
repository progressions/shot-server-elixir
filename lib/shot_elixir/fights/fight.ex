defmodule ShotElixir.Fights.Fight do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fights" do
    field :name, :string
    field :active, :boolean, default: true
    field :sequence, :integer, default: 1
    field :shot_counter, :integer, default: 18
    field :fight_type, :string, default: "fight"
    field :ended_at, :utc_datetime

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :location, ShotElixir.Sites.Site
    belongs_to :site, ShotElixir.Sites.Site

    has_many :shots, ShotElixir.Fights.Shot
    has_many :character_effects, ShotElixir.Effects.CharacterEffect

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(fight, attrs) do
    fight
    |> cast(attrs, [:name, :active, :sequence, :shot_counter, :fight_type,
                    :ended_at, :campaign_id, :location_id, :site_id])
    |> validate_required([:name, :campaign_id])
    |> validate_inclusion(:fight_type, ["fight", "chase"])
    |> validate_number(:shot_counter, greater_than_or_equal_to: 0)
    |> validate_number(:sequence, greater_than_or_equal_to: 1)
  end
end