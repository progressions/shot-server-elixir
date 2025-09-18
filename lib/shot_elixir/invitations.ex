defmodule ShotElixir.Invitations do
  @moduledoc """
  The Invitations context.
  """

  defmodule Invitation do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "invitations" do
      field :email, :string
      field :redeemed, :boolean, default: false
      field :redeemed_at, :naive_datetime

      belongs_to :user, ShotElixir.Accounts.User
      belongs_to :campaign, ShotElixir.Campaigns.Campaign

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end