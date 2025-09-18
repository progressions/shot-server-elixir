defmodule ShotElixir.Characters do
  @moduledoc """
  The Characters context.
  """

  defmodule Character do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "characters" do
      field :name, :string
      field :archetype, :string
      field :character_type, :string

      belongs_to :user, ShotElixir.Accounts.User
      belongs_to :campaign, ShotElixir.Campaigns.Campaign

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end