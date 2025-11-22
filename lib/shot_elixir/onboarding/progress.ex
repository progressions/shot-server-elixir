defmodule ShotElixir.Onboarding.Progress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "onboarding_progresses" do
    field :first_campaign_created_at, :utc_datetime
    field :first_campaign_activated_at, :utc_datetime
    field :first_character_created_at, :utc_datetime
    field :first_fight_created_at, :utc_datetime
    field :first_faction_created_at, :utc_datetime
    field :first_party_created_at, :utc_datetime
    field :first_site_created_at, :utc_datetime
    field :congratulations_dismissed_at, :utc_datetime

    belongs_to :user, ShotElixir.Accounts.User

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [
      :first_campaign_created_at,
      :first_campaign_activated_at,
      :first_character_created_at,
      :first_fight_created_at,
      :first_faction_created_at,
      :first_party_created_at,
      :first_site_created_at,
      :congratulations_dismissed_at,
      :user_id
    ])
    |> validate_required([:user_id])
  end

  @milestone_sequence [
    %{key: "campaign", timestamp_field: :first_campaign_created_at},
    %{key: "activate-campaign", timestamp_field: :first_campaign_activated_at},
    %{key: "character", timestamp_field: :first_character_created_at},
    %{key: "faction", timestamp_field: :first_faction_created_at},
    %{key: "party", timestamp_field: :first_party_created_at},
    %{key: "site", timestamp_field: :first_site_created_at},
    %{key: "fight", timestamp_field: :first_fight_created_at}
  ]

  def all_milestones_complete?(progress) do
    milestone_timestamps(progress)
    |> Enum.all?(fn timestamp -> timestamp != nil end)
  end

  def onboarding_complete?(progress) do
    all_milestones_complete?(progress) && progress.congratulations_dismissed_at != nil
  end

  def ready_for_congratulations?(progress) do
    all_milestones_complete?(progress) && progress.congratulations_dismissed_at == nil
  end

  def next_milestone(progress) do
    Enum.find(@milestone_sequence, fn milestone ->
      Map.get(progress, milestone.timestamp_field) == nil
    end)
  end

  defp milestone_timestamps(progress) do
    [
      progress.first_campaign_created_at,
      progress.first_campaign_activated_at,
      progress.first_character_created_at,
      progress.first_faction_created_at,
      progress.first_party_created_at,
      progress.first_site_created_at,
      progress.first_fight_created_at
    ]
  end
end
