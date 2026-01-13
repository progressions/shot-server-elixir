defmodule ShotElixir.Parties.Party do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "parties" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false
    field :image_url, :string, virtual: true
    field :notion_page_id, :string
    field :last_synced_to_notion_at, :utc_datetime

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction
    belongs_to :juncture, ShotElixir.Junctures.Juncture
    has_many :memberships, ShotElixir.Parties.Membership
    has_many :characters, through: [:memberships, :character]
    has_many :vehicles, through: [:memberships, :vehicle]

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Party"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(party, attrs) do
    party
    |> cast(attrs, [
      :name,
      :description,
      :active,
      :at_a_glance,
      :campaign_id,
      :faction_id,
      :juncture_id,
      :notion_page_id,
      :last_synced_to_notion_at
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:faction_id)
    |> foreign_key_constraint(:juncture_id)
    |> unique_constraint(:notion_page_id, name: :parties_notion_page_id_index)
  end

  @doc """
  Convert party to Notion page properties format.
  """
  def as_notion(%__MODULE__{} = party) do
    %{
      "Name" => %{"title" => [%{"text" => %{"content" => party.name || ""}}]},
      "Description" => %{"rich_text" => [%{"text" => %{"content" => party.description || ""}}]},
      "At a Glance" => %{"checkbox" => !!party.at_a_glance}
    }
  end
end
