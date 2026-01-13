defmodule ShotElixir.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset
  use Waffle.Ecto.Schema

  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sites" do
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
    has_many :attunements, ShotElixir.Sites.Attunement

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Site"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(site, attrs) do
    site
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
    |> unique_constraint(:notion_page_id, name: :sites_notion_page_id_index)
  end

  @doc """
  Convert site to Notion page properties format.
  """
  def as_notion(%__MODULE__{} = site) do
    base = %{
      "Name" => %{"title" => [%{"text" => %{"content" => site.name || ""}}]},
      "Description" => %{"rich_text" => [%{"text" => %{"content" => site.description || ""}}]},
      "At a Glance" => %{"checkbox" => !!site.at_a_glance}
    }

    if Ecto.assoc_loaded?(site.attunements) do
      character_ids =
        site.attunements
        |> Enum.map(fn a ->
          if Ecto.assoc_loaded?(a.character), do: a.character, else: nil
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.notion_page_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn id -> %{"id" => id} end)

      if Enum.any?(character_ids) do
        Map.put(base, "Characters", %{"relation" => character_ids})
      else
        base
      end
    else
      base
    end
  end

  @doc """
  Returns the image URL for a site, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = site) do
    site.image_url
  end
end
