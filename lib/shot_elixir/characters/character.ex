defmodule ShotElixir.Characters.Character do
  use Ecto.Schema
  import Ecto.Changeset
  use Waffle.Ecto.Schema
  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @default_action_values %{
    "Guns" => 0,
    "Martial Arts" => 0,
    "Sorcery" => 0,
    "Scroungetech" => 0,
    "Genome" => 0,
    "Mutant" => 0,
    "Creature" => 0,
    "Defense" => 0,
    "Toughness" => 0,
    "Speed" => 0,
    "Fortune" => 0,
    "Max Fortune" => 0,
    "FortuneType" => "Fortune",
    "MainAttack" => "Guns",
    "SecondaryAttack" => nil,
    "Wounds" => 0,
    "Type" => "PC",
    "Marks of Death" => 0,
    "Archetype" => "",
    "Damage" => 0
  }

  @default_description %{
    "Nicknames" => "",
    "Age" => "",
    "Height" => "",
    "Weight" => "",
    "Hair Color" => "",
    "Eye Color" => "",
    "Style of Dress" => "",
    "Appearance" => "",
    "Background" => "",
    "Melodramatic Hook" => ""
  }

  @character_types ["PC", "NPC", "Ally", "Mook", "Featured Foe", "Boss", "Uber-Boss"]

  @doc """
  Returns the default action values map for a new character.
  """
  def default_action_values, do: @default_action_values

  schema "characters" do
    field :name, :string
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false
    field :defense, :integer
    field :impairments, :integer, default: 0
    field :color, :string

    # JSONB fields
    field :action_values, :map, default: @default_action_values
    field :description, :map, default: %{}
    field :skills, :map, default: %{}
    field :status, {:array, :string}, default: []

    # Additional fields (image_url is provided virtually via external services)
    field :image_url, :string, virtual: true
    field :task, :boolean
    field :summary, :string
    field :wealth, :string
    field :is_template, :boolean, default: false
    field :extending, :boolean, default: false
    field :notion_page_id, Ecto.UUID
    field :last_synced_to_notion_at, :utc_datetime

    belongs_to :user, ShotElixir.Accounts.User
    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :faction, ShotElixir.Factions.Faction
    belongs_to :juncture, ShotElixir.Junctures.Juncture
    belongs_to :equipped_weapon, ShotElixir.Weapons.Weapon

    has_many :shots, ShotElixir.Fights.Shot
    has_many :fights, through: [:shots, :fight]
    has_many :character_effects, ShotElixir.Effects.CharacterEffect
    has_many :character_schticks, ShotElixir.Schticks.CharacterSchtick
    has_many :schticks, through: [:character_schticks, :schtick]
    has_many :advancements, ShotElixir.Characters.Advancement
    has_many :carries, ShotElixir.Weapons.Carry
    has_many :weapons, through: [:carries, :weapon]
    has_many :memberships, ShotElixir.Parties.Membership
    has_many :parties, through: [:memberships, :party]
    has_many :attunements, ShotElixir.Sites.Attunement
    has_many :sites, through: [:attunements, :site]

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Character"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [
      :name,
      :active,
      :at_a_glance,
      :defense,
      :impairments,
      :color,
      :action_values,
      :description,
      :skills,
      :status,
      :task,
      :summary,
      :wealth,
      :is_template,
      :extending,
      :notion_page_id,
      :last_synced_to_notion_at,
      :user_id,
      :campaign_id,
      :faction_id,
      :juncture_id,
      :equipped_weapon_id
    ])
    |> validate_required([:name, :campaign_id])
    |> validate_number(:impairments, greater_than_or_equal_to: 0)
    |> validate_character_type()
    |> unique_constraint([:name, :campaign_id])
    |> unique_constraint(:notion_page_id, name: :characters_notion_page_id_index)
    |> merge_partial_action_values()
    |> ensure_default_values()
  end

  @doc """
  Returns the image URL for a character, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = character) do
    character.image_url
  end

  defp validate_character_type(changeset) do
    action_values = get_field(changeset, :action_values) || %{}
    character_type = Map.get(action_values, "Type", "PC")

    if character_type in @character_types do
      changeset
    else
      add_error(changeset, :action_values, "invalid character type")
    end
  end

  # Merges partial action_values updates with existing values.
  # This allows updating just Wounds without wiping out Type, Creature, etc.
  defp merge_partial_action_values(changeset) do
    incoming_values = get_change(changeset, :action_values)

    if is_nil(incoming_values) do
      changeset
    else
      existing_values = changeset.data.action_values || %{}
      merged_values = Map.merge(existing_values, incoming_values)
      put_change(changeset, :action_values, merged_values)
    end
  end

  defp ensure_default_values(changeset) do
    changeset
    |> ensure_default_action_values()
    |> ensure_default_description()
  end

  defp ensure_default_action_values(changeset) do
    action_values = get_field(changeset, :action_values) || %{}
    # Filter out nil values so they don't overwrite defaults
    non_nil_values = action_values |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
    merged_values = Map.merge(@default_action_values, non_nil_values)
    put_change(changeset, :action_values, merged_values)
  end

  defp ensure_default_description(changeset) do
    description = get_field(changeset, :description) || %{}
    merged_description = Map.merge(@default_description, description)
    put_change(changeset, :description, merged_description)
  end

  # Notion Integration Functions

  @doc """
  Convert character to Notion property format for creating/updating Notion pages.
  """
  def as_notion(%__MODULE__{} = character) do
    av = character.action_values || @default_action_values
    desc = character.description || %{}
    # Ensure name is never nil for Notion API (titles cannot be nil)
    name = character.name || "Unnamed Character"

    base_properties = %{
      "Name" => %{"title" => [%{"type" => "text", "text" => %{"content" => name}}]},
      "Enemy Type" => %{"select" => %{"name" => av["Type"] || "PC"}},
      "Wounds" => %{"number" => to_number(av["Wounds"])},
      "Defense" => %{"number" => to_number(av["Defense"])},
      "Toughness" => %{"number" => to_number(av["Toughness"])},
      "Speed" => %{"number" => to_number(av["Speed"])},
      "Fortune" => %{"number" => to_number(av["Max Fortune"])},
      "Guns" => %{"number" => to_number(av["Guns"])},
      "Martial Arts" => %{"number" => to_number(av["Martial Arts"])},
      "Sorcery" => %{"number" => to_number(av["Sorcery"])},
      "Mutant" => %{"number" => to_number(av["Mutant"])},
      "Scroungetech" => %{"number" => to_number(av["Scroungetech"])},
      "Creature" => %{"number" => to_number(av["Creature"])},
      "Inactive" => %{"checkbox" => !character.active},
      "At a Glance" => %{"checkbox" => !!character.at_a_glance},
      "Tags" => %{"multi_select" => tags_for_notion(character)}
    }

    # Add rich_text fields only if they have content (Notion rejects empty rich_text)
    base_properties
    |> maybe_add_rich_text("Damage", to_string(av["Damage"] || ""))
    |> maybe_add_rich_text("Age", to_string(desc["Age"] || ""))
    |> maybe_add_rich_text("Nicknames", to_string(desc["Nicknames"] || ""))
    |> maybe_add_rich_text("Height", to_string(desc["Height"] || ""))
    |> maybe_add_rich_text("Weight", to_string(desc["Weight"] || ""))
    |> maybe_add_rich_text("Hair Color", to_string(desc["Hair Color"] || ""))
    |> maybe_add_rich_text("Eye Color", to_string(desc["Eye Color"] || ""))
    |> maybe_add_rich_text("Style of Dress", to_string(desc["Style of Dress"] || ""))
    |> maybe_add_rich_text("Melodramatic Hook", strip_html(desc["Melodramatic Hook"] || ""))
    |> maybe_add_rich_text("Description", strip_html(desc["Appearance"] || ""))
    |> maybe_add_select("MainAttack", av["MainAttack"])
    |> maybe_add_select("SecondaryAttack", av["SecondaryAttack"])
    |> maybe_add_select("FortuneType", av["FortuneType"])
    |> maybe_add_archetype(av["Archetype"])
    |> maybe_add_chi_war_link(character)
  end

  # Only add rich_text property if value is not empty
  defp maybe_add_rich_text(properties, _key, nil), do: properties
  defp maybe_add_rich_text(properties, _key, ""), do: properties

  defp maybe_add_rich_text(properties, key, value) do
    Map.put(properties, key, %{
      "rich_text" => [%{"type" => "text", "text" => %{"content" => value}}]
    })
  end

  # Convert string values to numbers for Notion API
  # Notion number fields require actual numbers, not strings
  defp to_number(nil), do: nil
  defp to_number(""), do: nil
  defp to_number(value) when is_integer(value), do: value
  defp to_number(value) when is_float(value), do: value

  defp to_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      {_int, _rest} -> nil
      :error -> nil
    end
  end

  defp to_number(_), do: nil

  defp tags_for_notion(character) do
    av = character.action_values || @default_action_values
    character_type = av["Type"]

    tags = [%{"name" => character_type}]
    tags = if character_type != "PC", do: [%{"name" => "NPC"} | tags], else: tags

    tags
  end

  defp maybe_add_select(properties, _key, nil), do: properties
  defp maybe_add_select(properties, _key, ""), do: properties

  defp maybe_add_select(properties, key, value) do
    Map.put(properties, key, %{"select" => %{"name" => value}})
  end

  defp maybe_add_archetype(properties, nil), do: properties
  defp maybe_add_archetype(properties, ""), do: properties

  defp maybe_add_archetype(properties, archetype) do
    Map.put(properties, "Type", %{
      "rich_text" => [%{"type" => "text", "text" => %{"content" => archetype}}]
    })
  end

  defp maybe_add_chi_war_link(properties, character) do
    if Application.get_env(:shot_elixir, :environment) == :prod do
      url = "https://chiwar.net/characters/#{character.id}"
      Map.put(properties, "Chi War Link", %{"url" => url})
    else
      properties
    end
  end

  defp strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  defp strip_html(_), do: ""

  @doc """
  Extract character attributes from Notion page properties.
  Merges Notion data with existing character data, preserving local values > 7.
  Filters out nil values to avoid overwriting defaults with nil.
  """
  def attributes_from_notion(character, page) do
    props = page["properties"]

    av =
      %{
        "Archetype" => get_rich_text(props, "Type"),
        "Type" => get_select(props, "Enemy Type"),
        "MainAttack" => get_select(props, "MainAttack"),
        "SecondaryAttack" => get_select(props, "SecondaryAttack"),
        "FortuneType" => get_select(props, "FortuneType"),
        "Fortune" => av_or_new(character, "Fortune", get_number(props, "Fortune")),
        "Max Fortune" => av_or_new(character, "Max Fortune", get_number(props, "Fortune")),
        "Wounds" => av_or_new(character, "Wounds", get_number(props, "Wounds")),
        "Defense" => av_or_new(character, "Defense", get_number(props, "Defense")),
        "Toughness" => av_or_new(character, "Toughness", get_number(props, "Toughness")),
        "Speed" => av_or_new(character, "Speed", get_number(props, "Speed")),
        "Guns" => av_or_new(character, "Guns", get_number(props, "Guns")),
        "Martial Arts" => av_or_new(character, "Martial Arts", get_number(props, "Martial Arts")),
        "Sorcery" => av_or_new(character, "Sorcery", get_number(props, "Sorcery")),
        "Creature" => av_or_new(character, "Creature", get_number(props, "Creature")),
        "Scroungetech" => av_or_new(character, "Scroungetech", get_number(props, "Scroungetech")),
        "Mutant" => av_or_new(character, "Mutant", get_number(props, "Mutant")),
        "Damage" => av_or_new(character, "Damage", get_number(props, "Damage"))
      }
      # Filter out nil values to preserve defaults
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    description =
      %{
        "Age" => get_rich_text(props, "Age"),
        "Height" => get_rich_text(props, "Height"),
        "Weight" => get_rich_text(props, "Weight"),
        "Eye Color" => get_rich_text(props, "Eye Color"),
        "Hair Color" => get_rich_text(props, "Hair Color"),
        "Appearance" => get_rich_text(props, "Description"),
        "Style of Dress" => get_rich_text(props, "Style of Dress"),
        "Melodramatic Hook" => get_rich_text(props, "Melodramatic Hook")
      }
      # Filter out empty strings to preserve existing description values
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    %{
      notion_page_id: page["id"],
      name: get_title(props, "Name"),
      action_values: Map.merge(character.action_values || @default_action_values, av),
      description: Map.merge(character.description || %{}, description)
    }
    |> maybe_put_at_a_glance(get_checkbox(props, "At a Glance"))
  end

  defp av_or_new(_character, _key, nil), do: nil

  defp av_or_new(character, key, new_value) do
    current = (character.action_values || @default_action_values)[key]

    cond do
      is_integer(current) and current > 7 -> current
      true -> new_value
    end
  end

  defp get_title(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("title", [])
    |> List.first()
    |> case do
      nil -> nil
      item -> get_in(item, ["plain_text"])
    end
  end

  defp get_select(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("select")
    |> case do
      nil -> nil
      %{"name" => name} -> name
      _ -> nil
    end
  end

  defp get_number(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("number")
  end

  defp get_checkbox(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("checkbox")
  end

  @doc false
  def maybe_put_at_a_glance(attrs, at_a_glance) do
    if is_boolean(at_a_glance) do
      Map.put(attrs, :at_a_glance, at_a_glance)
    else
      attrs
    end
  end

  defp get_rich_text(props, key) do
    props
    |> Map.get(key, %{})
    |> Map.get("rich_text", [])
    |> Enum.map(& &1["plain_text"])
    |> Enum.join("")
  end
end
