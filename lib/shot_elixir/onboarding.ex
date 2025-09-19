defmodule ShotElixir.Onboarding do
  @moduledoc """
  The Onboarding context for tracking user onboarding progress.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo

  def get_user_onboarding_progress(user_id) do
    __MODULE__.Progress
    |> where([p], p.user_id == ^user_id)
    |> Repo.one()
  end

  def ensure_onboarding_progress!(user) do
    case get_user_onboarding_progress(user.id) do
      nil ->
        case create_progress(user) do
          {:ok, progress} -> progress
        end

      progress ->
        progress
    end
  end

  def create_progress(user) do
    # TODO: Fix struct reference issue
    {:ok, %{id: Ecto.UUID.generate(), user_id: user.id}}
  end

  def update_progress(progress, attrs) do
    # TODO: Fix struct reference issue
    {:ok, Map.merge(progress, attrs)}
  end

  def dismiss_congratulations(progress) do
    # TODO: Fix struct reference issue
    {:ok, Map.put(progress, :congratulations_dismissed_at, DateTime.utc_now())}
  end

  defmodule Progress do
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
  end
end
