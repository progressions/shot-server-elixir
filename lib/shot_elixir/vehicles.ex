defmodule ShotElixir.Vehicles do
  @moduledoc """
  The Vehicles context.
  """

  defmodule Vehicle do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "vehicles" do
      field :name, :string
      field :archetype, :string

      belongs_to :user, ShotElixir.Accounts.User
      belongs_to :campaign, ShotElixir.Campaigns.Campaign

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end