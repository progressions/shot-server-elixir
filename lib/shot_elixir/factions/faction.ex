defmodule ShotElixir.Factions.Faction do
  use Ecto.Schema
  import Ecto.Changeset
  use Arc.Ecto.Schema

  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Junctures.Juncture

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "factions" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false
    field :image_url, :string, virtual: true
    field :notion_page_id, :string
    field :last_synced_to_notion_at, :utc_datetime

    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    has_many :characters, Character
    has_many :vehicles, Vehicle
    has_many :sites, Site
    has_many :parties, Party
    has_many :junctures, Juncture

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Faction"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(faction, attrs) do
    faction
    |> cast(attrs, [
      :name,
      :description,
      :active,
      :at_a_glance,
      :campaign_id,
      :notion_page_id,
      :last_synced_to_notion_at
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:notion_page_id, name: :factions_notion_page_id_index)
  end

  @doc """
  Convert faction to Notion page properties format.
  Note: Factions in Notion use rich_text for Name, not title.
  """
  def as_notion(%__MODULE__{} = faction) do
    %{
      "Name" => %{"rich_text" => [%{"text" => %{"content" => faction.name || ""}}]},
      "Description" => %{"rich_text" => [%{"text" => %{"content" => faction.description || ""}}]}
    }
  end

  @doc """
  Returns the image URL for a faction, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = faction) do
    faction.image_url
  end
end
