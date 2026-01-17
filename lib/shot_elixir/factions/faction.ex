defmodule ShotElixir.Factions.Faction do
  use Ecto.Schema
  import Ecto.Changeset
  use Waffle.Ecto.Schema

  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Helpers.MentionConverter
  import ShotElixir.Helpers.Html, only: [strip_html: 1]

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

    # Rich content from Notion (read-only in chi-war)
    field :rich_description, :string
    field :mentions, :map, default: %{}

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
      :last_synced_to_notion_at,
      :rich_description,
      :mentions
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint(:notion_page_id, name: :factions_notion_page_id_index)
  end

  @doc """
  Convert faction to Notion page properties format.
  Note: Factions in Notion use rich_text for Name, not title.

  If campaign is preloaded, uses MentionConverter to convert @mentions to Notion page links.
  Otherwise, falls back to simple HTML stripping.
  """
  def as_notion(%__MODULE__{} = faction) do
    # Check if campaign is preloaded - if so, use mention-aware conversion
    if Ecto.assoc_loaded?(faction.campaign) and faction.campaign != nil do
      as_notion(faction, faction.campaign)
    else
      as_notion_simple(faction)
    end
  end

  @doc """
  Convert faction to Notion page properties format with mention support.
  Uses MentionConverter to convert @mentions to Notion page links.
  """
  def as_notion(%__MODULE__{} = faction, %ShotElixir.Campaigns.Campaign{} = campaign) do
    description_rich_text =
      MentionConverter.html_to_notion_rich_text(faction.description || "", campaign)

    description_rich_text =
      if Enum.empty?(description_rich_text) do
        [%{"text" => %{"content" => ""}}]
      else
        description_rich_text
      end

    base = %{
      "Name" => %{"rich_text" => [%{"text" => %{"content" => faction.name || ""}}]},
      "Description" => %{"rich_text" => description_rich_text},
      "At a Glance" => %{"checkbox" => !!faction.at_a_glance}
    }

    maybe_add_character_relations(base, faction)
  end

  # Simple version without mention conversion (fallback)
  defp as_notion_simple(%__MODULE__{} = faction) do
    base = %{
      "Name" => %{"rich_text" => [%{"text" => %{"content" => faction.name || ""}}]},
      "Description" => %{
        "rich_text" => [%{"text" => %{"content" => strip_html(faction.description || "")}}]
      },
      "At a Glance" => %{"checkbox" => !!faction.at_a_glance}
    }

    maybe_add_character_relations(base, faction)
  end

  # Helper to add character relations to base properties
  defp maybe_add_character_relations(base, faction) do
    if Ecto.assoc_loaded?(faction.characters) do
      character_ids =
        faction.characters
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
  Returns the image URL for a faction, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = faction) do
    faction.image_url
  end
end
