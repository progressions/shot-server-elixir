defmodule ShotElixir.Adventures.Adventure do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Helpers.MentionConverter
  import ShotElixir.Helpers.Html, only: [strip_html: 1]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "adventures" do
    field :name, :string
    field :description, :string
    field :season, :integer
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false
    field :image_url, :string, virtual: true
    field :notion_page_id, :string
    field :last_synced_to_notion_at, :utc_datetime

    # Rich content from Notion (read-only in chi-war)
    field :rich_description, :string
    field :mentions, :map, default: %{}

    # Virtual fields for relationship IDs
    field :character_ids, {:array, :binary_id}, virtual: true, default: []
    field :villain_ids, {:array, :binary_id}, virtual: true, default: []
    field :fight_ids, {:array, :binary_id}, virtual: true, default: []

    belongs_to :user, ShotElixir.Accounts.User
    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    has_many :adventure_characters, ShotElixir.Adventures.AdventureCharacter
    has_many :characters, through: [:adventure_characters, :character]
    has_many :adventure_villains, ShotElixir.Adventures.AdventureVillain
    has_many :villains, through: [:adventure_villains, :character]
    has_many :adventure_fights, ShotElixir.Adventures.AdventureFight
    has_many :fights, through: [:adventure_fights, :fight]

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Adventure"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(adventure, attrs) do
    adventure
    |> cast(attrs, [
      :name,
      :description,
      :season,
      :started_at,
      :ended_at,
      :active,
      :at_a_glance,
      :user_id,
      :campaign_id,
      :notion_page_id,
      :last_synced_to_notion_at,
      :rich_description,
      :mentions
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:notion_page_id, name: :adventures_notion_page_id_index)
  end

  @doc """
  Convert adventure to Notion page properties format.

  If campaign is preloaded, uses MentionConverter to convert @mentions to Notion page links.
  Otherwise, falls back to simple HTML stripping.
  """
  def as_notion(%__MODULE__{} = adventure) do
    # Check if campaign is preloaded - if so, use mention-aware conversion
    if Ecto.assoc_loaded?(adventure.campaign) and adventure.campaign != nil do
      as_notion(adventure, adventure.campaign)
    else
      as_notion_simple(adventure)
    end
  end

  @doc """
  Convert adventure to Notion page properties format with mention support.
  Uses MentionConverter to convert @mentions to Notion page links.
  """
  def as_notion(%__MODULE__{} = adventure, %ShotElixir.Campaigns.Campaign{} = campaign) do
    description_rich_text =
      MentionConverter.html_to_notion_rich_text(adventure.description || "", campaign)

    description_rich_text =
      if Enum.empty?(description_rich_text) do
        [%{"text" => %{"content" => ""}}]
      else
        description_rich_text
      end

    base = %{
      "Name" => %{"title" => [%{"text" => %{"content" => adventure.name || ""}}]},
      "Description" => %{"rich_text" => description_rich_text},
      "At a Glance" => %{"checkbox" => !!adventure.at_a_glance}
    }

    maybe_add_optional_fields(base, adventure)
  end

  # Simple version without mention conversion (fallback)
  defp as_notion_simple(%__MODULE__{} = adventure) do
    base = %{
      "Name" => %{"title" => [%{"text" => %{"content" => adventure.name || ""}}]},
      "Description" => %{
        "rich_text" => [%{"text" => %{"content" => strip_html(adventure.description || "")}}]
      },
      "At a Glance" => %{"checkbox" => !!adventure.at_a_glance}
    }

    maybe_add_optional_fields(base, adventure)
  end

  # Helper to add optional fields (season, dates)
  defp maybe_add_optional_fields(base, adventure) do
    base =
      if adventure.season do
        Map.put(base, "Season", %{"number" => adventure.season})
      else
        base
      end

    base =
      if adventure.started_at do
        Map.put(base, "Started", %{
          "date" => %{"start" => DateTime.to_iso8601(adventure.started_at)}
        })
      else
        base
      end

    if adventure.ended_at do
      Map.put(base, "Ended", %{"date" => %{"start" => DateTime.to_iso8601(adventure.ended_at)}})
    else
      base
    end
  end
end
