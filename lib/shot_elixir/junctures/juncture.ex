defmodule ShotElixir.Junctures.Juncture do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Helpers.MentionConverter
  alias ShotElixir.Services.Notion.Mappers, as: NotionMappers
  import ShotElixir.Helpers.Html, only: [strip_html: 1]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "junctures" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false
    field :notion_page_id, :binary_id

    # Rich content from Notion (read-only in chi-war)
    field :rich_description, :string
    field :rich_description_gm_only, :string
    field :mentions, :map, default: %{}

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction

    has_many :characters, ShotElixir.Characters.Character, foreign_key: :juncture_id
    has_many :vehicles, ShotElixir.Vehicles.Vehicle, foreign_key: :juncture_id

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Juncture"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(juncture, attrs) do
    juncture
    |> cast(attrs, [
      :name,
      :description,
      :active,
      :at_a_glance,
      :notion_page_id,
      :campaign_id,
      :faction_id,
      :rich_description,
      :rich_description_gm_only,
      :mentions
    ])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Convert juncture to Notion page properties format.

  If campaign is preloaded, uses MentionConverter to convert @mentions to Notion page links.
  Otherwise, falls back to simple HTML stripping.
  """
  def as_notion(%__MODULE__{} = juncture) do
    # Check if campaign is preloaded - if so, use mention-aware conversion
    if Ecto.assoc_loaded?(juncture.campaign) and juncture.campaign != nil do
      as_notion(juncture, juncture.campaign)
    else
      as_notion_simple(juncture)
    end
  end

  @doc """
  Convert juncture to Notion page properties format with mention support.
  Uses MentionConverter to convert @mentions to Notion page links.
  """
  def as_notion(%__MODULE__{} = juncture, %ShotElixir.Campaigns.Campaign{} = campaign) do
    description_rich_text =
      MentionConverter.html_to_notion_rich_text(juncture.description || "", campaign)

    description_rich_text =
      if Enum.empty?(description_rich_text) do
        [%{"text" => %{"content" => ""}}]
      else
        description_rich_text
      end

    %{
      "Name" => %{"title" => [%{"text" => %{"content" => juncture.name || ""}}]},
      "Description" => %{"rich_text" => description_rich_text},
      "At a Glance" => %{"checkbox" => !!juncture.at_a_glance}
    }
    |> NotionMappers.maybe_add_faction_relation(juncture)
    |> NotionMappers.maybe_add_chi_war_link("junctures", juncture)
  end

  # Simple version without mention conversion (fallback)
  defp as_notion_simple(%__MODULE__{} = juncture) do
    %{
      "Name" => %{"title" => [%{"text" => %{"content" => juncture.name || ""}}]},
      "Description" => %{
        "rich_text" => [%{"text" => %{"content" => strip_html(juncture.description || "")}}]
      },
      "At a Glance" => %{"checkbox" => !!juncture.at_a_glance}
    }
    |> NotionMappers.maybe_add_faction_relation(juncture)
    |> NotionMappers.maybe_add_chi_war_link("junctures", juncture)
  end
end
