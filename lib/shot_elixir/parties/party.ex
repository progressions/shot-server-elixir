defmodule ShotElixir.Parties.Party do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Helpers.MentionConverter
  alias ShotElixir.Services.Notion.Mappers, as: NotionMappers
  import ShotElixir.Helpers.Html, only: [strip_html: 1]

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

    # Rich content from Notion (read-only in chi-war)
    field :rich_description, :string
    field :mentions, :map, default: %{}

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
      :last_synced_to_notion_at,
      :rich_description,
      :mentions
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
  Requires [:memberships, :character] to be preloaded for the "Characters" relation to be populated.

  If campaign is preloaded, uses MentionConverter to convert @mentions to Notion page links.
  Otherwise, falls back to simple HTML stripping.
  """
  def as_notion(%__MODULE__{} = party) do
    # Check if campaign is preloaded - if so, use mention-aware conversion
    if Ecto.assoc_loaded?(party.campaign) and party.campaign != nil do
      as_notion(party, party.campaign)
    else
      as_notion_simple(party)
    end
  end

  @doc """
  Convert party to Notion page properties format with mention support.
  Uses MentionConverter to convert @mentions to Notion page links.
  """
  def as_notion(%__MODULE__{} = party, %ShotElixir.Campaigns.Campaign{} = campaign) do
    description_rich_text =
      MentionConverter.html_to_notion_rich_text(party.description || "", campaign)

    description_rich_text =
      if Enum.empty?(description_rich_text) do
        [%{"text" => %{"content" => ""}}]
      else
        description_rich_text
      end

    base = %{
      "Name" => %{"title" => [%{"text" => %{"content" => party.name || ""}}]},
      "Description" => %{"rich_text" => description_rich_text},
      "At a Glance" => %{"checkbox" => !!party.at_a_glance}
    }

    base
    |> maybe_add_character_relations(party)
    |> NotionMappers.maybe_add_faction_relation(party)
    |> NotionMappers.maybe_add_juncture_relation(party)
  end

  # Simple version without mention conversion (fallback)
  defp as_notion_simple(%__MODULE__{} = party) do
    base = %{
      "Name" => %{"title" => [%{"text" => %{"content" => party.name || ""}}]},
      "Description" => %{
        "rich_text" => [%{"text" => %{"content" => strip_html(party.description || "")}}]
      },
      "At a Glance" => %{"checkbox" => !!party.at_a_glance}
    }

    base
    |> maybe_add_character_relations(party)
    |> NotionMappers.maybe_add_faction_relation(party)
    |> NotionMappers.maybe_add_juncture_relation(party)
  end

  # Helper to add character relations to base properties
  defp maybe_add_character_relations(base, party) do
    if Ecto.assoc_loaded?(party.memberships) do
      character_ids =
        party.memberships
        |> Enum.map(fn m ->
          if Ecto.assoc_loaded?(m.character), do: m.character, else: nil
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
end
