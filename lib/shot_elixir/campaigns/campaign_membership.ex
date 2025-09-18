defmodule ShotElixir.Campaigns.CampaignMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
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
    |> validate_unique_membership()
    |> unique_constraint([:campaign_id, :user_id], name: :index_campaign_memberships_on_campaign_id_and_user_id)
  end

  defp validate_unique_membership(changeset) do
    case {get_field(changeset, :user_id), get_field(changeset, :campaign_id)} do
      {nil, _} -> changeset
      {_, nil} -> changeset
      {user_id, campaign_id} ->
        alias ShotElixir.Repo
        import Ecto.Query

        if Repo.exists?(from cm in __MODULE__,
             where: cm.user_id == ^user_id and cm.campaign_id == ^campaign_id) do
          add_error(changeset, :user_id, "has already been taken")
        else
          changeset
        end
    end
  end
end