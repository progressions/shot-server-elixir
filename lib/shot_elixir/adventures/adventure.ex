defmodule ShotElixir.Adventures.Adventure do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.ImagePositions.ImagePosition
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
      :last_synced_to_notion_at
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:notion_page_id, name: :adventures_notion_page_id_index)
  end

  @doc """
  Convert adventure to Notion page properties format.
  """
  def as_notion(%__MODULE__{} = adventure) do
    base = %{
      "Name" => %{"title" => [%{"text" => %{"content" => adventure.name || ""}}]},
      "Description" => %{
        "rich_text" => [%{"text" => %{"content" => strip_html(adventure.description || "")}}]
      },
      "At a Glance" => %{"checkbox" => !!adventure.at_a_glance}
    }

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

  @doc """
  Merge attributes from a Notion page into adventure attributes.
  """
  def attributes_from_notion(page, existing_adventure \\ nil) do
    props = page["properties"] || %{}

    attrs = %{
      notion_page_id: page["id"],
      last_synced_to_notion_at: DateTime.utc_now()
    }

    # Name from title property
    attrs =
      case get_in(props, ["Name", "title"]) do
        [%{"text" => %{"content" => name}} | _] when name != "" ->
          Map.put(attrs, :name, name)

        _ ->
          if existing_adventure, do: attrs, else: Map.put(attrs, :name, "Untitled Adventure")
      end

    # Description from rich_text (using plain_text to handle all rich_text types)
    attrs =
      case get_in(props, ["Description", "rich_text"]) do
        rich_text when is_list(rich_text) and length(rich_text) > 0 ->
          description =
            rich_text
            |> Enum.map(& &1["plain_text"])
            |> Enum.join("")

          Map.put(attrs, :description, description)

        _ ->
          attrs
      end

    # Season from number
    attrs =
      case get_in(props, ["Season", "number"]) do
        season when is_integer(season) -> Map.put(attrs, :season, season)
        _ -> attrs
      end

    # At a Glance from checkbox
    attrs =
      case get_in(props, ["At a Glance", "checkbox"]) do
        value when is_boolean(value) -> Map.put(attrs, :at_a_glance, value)
        _ -> attrs
      end

    # Started date
    attrs =
      case get_in(props, ["Started", "date", "start"]) do
        date_str when is_binary(date_str) ->
          case DateTime.from_iso8601(date_str) do
            {:ok, dt, _} -> Map.put(attrs, :started_at, dt)
            _ -> attrs
          end

        _ ->
          attrs
      end

    # Ended date
    case get_in(props, ["Ended", "date", "start"]) do
      date_str when is_binary(date_str) ->
        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> Map.put(attrs, :ended_at, dt)
          _ -> attrs
        end

      _ ->
        attrs
    end
  end
end
