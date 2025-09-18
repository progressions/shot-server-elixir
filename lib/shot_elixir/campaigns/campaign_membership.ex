defmodule ShotElixir.Campaigns.CampaignMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "campaign_memberships" do
    belongs_to :user, ShotElixir.Accounts.User
    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:user_id, :campaign_id])
    |> validate_required([:user_id, :campaign_id])
    |> unique_constraint([:user_id, :campaign_id])
  end
end