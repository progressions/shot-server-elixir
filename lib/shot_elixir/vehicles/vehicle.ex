defmodule ShotElixir.Vehicles.Vehicle do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vehicles" do
    field :name, :string
    field :action_values, :map
    field :color, :string
    field :impairments, :integer, default: 0
    field :active, :boolean, default: true
    field :image_url, :string
    field :task, :boolean, default: false
    field :notion_page_id, :binary_id
    field :last_synced_to_notion_at, :utc_datetime
    field :summary, :string
    field :description, :map

    belongs_to :user, ShotElixir.Accounts.User
    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction
    belongs_to :juncture, ShotElixir.Junctures.Juncture

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(vehicle, attrs) do
    vehicle
    |> cast(attrs, [
      :name,
      :action_values,
      :color,
      :impairments,
      :active,
      :image_url,
      :task,
      :notion_page_id,
      :last_synced_to_notion_at,
      :summary,
      :description,
      :user_id,
      :campaign_id,
      :faction_id,
      :juncture_id
    ])
    |> validate_required([:name, :action_values, :campaign_id])
  end
end
