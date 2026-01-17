defmodule ShotElixir.Campaigns.Campaign do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias ShotElixir.Repo
  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "campaigns" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :at_a_glance, :boolean, default: false
    field :is_master_template, :boolean, default: false
    field :seeded_at, :naive_datetime

    # Seeding status tracking
    field :seeding_status, :string
    field :seeding_images_total, :integer, default: 0
    field :seeding_images_completed, :integer, default: 0

    # Batch image generation tracking
    field :batch_image_status, :string
    field :batch_images_total, :integer, default: 0
    field :batch_images_completed, :integer, default: 0

    # Provider-agnostic AI credit exhaustion tracking
    field :ai_credits_exhausted_at, :utc_datetime
    field :ai_credits_exhausted_provider, :string
    field :ai_credits_exhausted_notified_at, :utc_datetime

    # AI generation toggle
    field :ai_generation_enabled, :boolean, default: true

    # AI provider selection (grok, openai, gemini, or nil)
    field :ai_provider, :string

    # Notion Integration (OAuth)
    field :notion_access_token, ShotElixir.Encrypted.Binary
    field :notion_bot_id, :string
    field :notion_workspace_name, :string
    field :notion_workspace_icon, :string
    field :notion_owner, :map
    field :notion_database_ids, :map, default: %{}
    field :notion_status, :string, default: "disconnected"

    # Notion failure tracking (for notification throttling)
    field :notion_failure_count, :integer, default: 0
    field :notion_failure_window_start, :utc_datetime

    belongs_to :user, ShotElixir.Accounts.User

    has_many :campaign_memberships, ShotElixir.Campaigns.CampaignMembership
    has_many :members, through: [:campaign_memberships, :user]
    has_many :fights, ShotElixir.Fights.Fight
    has_many :characters, ShotElixir.Characters.Character
    has_many :vehicles, ShotElixir.Vehicles.Vehicle
    has_many :invitations, ShotElixir.Invitations.Invitation
    has_many :schticks, ShotElixir.Schticks.Schtick
    has_many :weapons, ShotElixir.Weapons.Weapon
    has_many :parties, ShotElixir.Parties.Party
    has_many :sites, ShotElixir.Sites.Site
    has_many :factions, ShotElixir.Factions.Faction
    has_many :junctures, ShotElixir.Junctures.Juncture

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "Campaign"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @valid_ai_providers ["grok", "openai", "gemini"]
  @valid_notion_statuses ["working", "disconnected", "needs_attention"]

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :name,
      :description,
      :active,
      :at_a_glance,
      :is_master_template,
      :user_id,
      :seeding_status,
      :seeding_images_total,
      :seeding_images_completed,
      :seeded_at,
      :batch_image_status,
      :batch_images_total,
      :batch_images_completed,
      :ai_credits_exhausted_at,
      :ai_credits_exhausted_provider,
      :ai_credits_exhausted_notified_at,
      :ai_generation_enabled,
      :ai_provider,
      :notion_access_token,
      :notion_bot_id,
      :notion_workspace_name,
      :notion_workspace_icon,
      :notion_owner,
      :notion_database_ids,
      :notion_status,
      :notion_failure_count,
      :notion_failure_window_start
    ])
    |> validate_required([:name, :user_id])
    |> validate_inclusion(:ai_provider, @valid_ai_providers ++ [nil])
    |> validate_inclusion(:notion_status, @valid_notion_statuses ++ [nil])
    |> validate_unique_name_per_user()
    |> validate_only_one_master_template()
  end

  @doc """
  Returns true if the campaign is currently being seeded (status is not nil and not "complete").
  """
  def seeding?(%__MODULE__{seeding_status: nil}), do: false
  def seeding?(%__MODULE__{seeding_status: "complete"}), do: false
  def seeding?(%__MODULE__{seeding_status: _}), do: true

  @doc """
  Returns true if the campaign has been fully seeded (seeded_at is not nil).
  """
  def seeded?(%__MODULE__{seeded_at: nil}), do: false
  def seeded?(%__MODULE__{seeded_at: _}), do: true

  @doc """
  Returns true if batch image generation is currently in progress.
  """
  def batch_images_in_progress?(%__MODULE__{batch_image_status: nil}), do: false
  def batch_images_in_progress?(%__MODULE__{batch_image_status: "complete"}), do: false
  def batch_images_in_progress?(%__MODULE__{batch_image_status: _}), do: true

  @doc """
  Returns true if any AI provider's credits were exhausted within the last 24 hours.
  """
  @credit_exhausted_window_hours 24
  def ai_credits_exhausted?(%__MODULE__{ai_credits_exhausted_at: nil}), do: false

  def ai_credits_exhausted?(%__MODULE__{ai_credits_exhausted_at: exhausted_at}) do
    hours_since = DateTime.diff(DateTime.utc_now(), exhausted_at, :hour)
    hours_since < @credit_exhausted_window_hours
  end

  defp validate_unique_name_per_user(changeset) do
    case {get_field(changeset, :name), get_field(changeset, :user_id)} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {name, user_id} ->
        existing_query =
          from c in __MODULE__,
            where: c.name == ^name and c.user_id == ^user_id

        # If we're updating, exclude current record
        existing_query =
          case get_field(changeset, :id) do
            nil -> existing_query
            id -> from c in existing_query, where: c.id != ^id
          end

        if Repo.exists?(existing_query) do
          add_error(changeset, :name, "has already been taken")
        else
          changeset
        end
    end
  end

  defp validate_only_one_master_template(changeset) do
    case get_change(changeset, :is_master_template) do
      true ->
        validate_change(changeset, :is_master_template, fn _, _ ->
          case Repo.exists?(from c in __MODULE__, where: c.is_master_template == true) do
            true -> [is_master_template: "can only be true for one campaign at a time"]
            false -> []
          end
        end)

      _ ->
        changeset
    end
  end
end
