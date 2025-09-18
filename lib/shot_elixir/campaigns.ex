defmodule ShotElixir.Campaigns do
  @moduledoc """
  The Campaigns context.
  """

  defmodule Campaign do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "campaigns" do
      field :name, :string
      field :description, :string
      field :active, :boolean, default: true
      field :is_master_template, :boolean, default: false
      field :seeded_at, :naive_datetime

      belongs_to :user, ShotElixir.Accounts.User

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end

  defmodule CampaignMembership do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "campaign_memberships" do
      belongs_to :user, ShotElixir.Accounts.User
      belongs_to :campaign, Campaign

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end
  end
end