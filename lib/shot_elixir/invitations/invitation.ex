defmodule ShotElixir.Invitations.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invitations" do
    field :email, :string
    field :redeemed, :boolean, default: false
    field :redeemed_at, :naive_datetime

    belongs_to :user, ShotElixir.Accounts.User
    belongs_to :pending_user, ShotElixir.Accounts.User
    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :redeemed, :redeemed_at, :user_id, :pending_user_id, :campaign_id])
    |> validate_required([:email, :user_id, :campaign_id])
    |> validate_format(:email, ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/)
    |> validate_length(:email, max: 254)
    |> unique_constraint([:email, :campaign_id],
      message: "An invitation for this email already exists for this campaign"
    )
  end
end
