defmodule ShotElixir.Onboarding do
  @moduledoc """
  The Onboarding context for tracking user onboarding progress.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Onboarding.Progress

  def get_user_onboarding_progress(user_id) do
    Progress
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
    %Progress{}
    |> Progress.changeset(%{user_id: user.id})
    |> Repo.insert()
  end

  def update_progress(progress, attrs) do
    progress
    |> Progress.changeset(attrs)
    |> Repo.update()
  end

  def dismiss_congratulations(progress) do
    update_progress(progress, %{congratulations_dismissed_at: DateTime.utc_now()})
  end
end
