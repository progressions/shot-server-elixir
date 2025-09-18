defmodule ShotElixir.Onboarding do
  @moduledoc """
  The Onboarding context for tracking user onboarding progress.
  """

  alias ShotElixir.Repo

  defmodule Progress do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "onboarding_progresses" do
      field :step, :string, default: "initial"
      field :completed, :boolean, default: false
      field :congratulations_dismissed, :boolean, default: false

      belongs_to :user, ShotElixir.Accounts.User

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(progress, attrs) do
      progress
      |> cast(attrs, [:step, :completed, :congratulations_dismissed, :user_id])
      |> validate_required([:user_id])
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
end
