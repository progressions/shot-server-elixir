defmodule ShotElixir.Campaigns.Campaign do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias ShotElixir.Repo

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "campaigns" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :is_master_template, :boolean, default: false
    field :seeded_at, :naive_datetime

    belongs_to :user, ShotElixir.Accounts.User

    has_many :campaign_memberships, ShotElixir.Campaigns.CampaignMembership
    has_many :members, through: [:campaign_memberships, :user]
    has_many :fights, ShotElixir.Fights.Fight
    has_many :characters, ShotElixir.Characters.Character
    has_many :vehicles, ShotElixir.Vehicles.Vehicle
    has_many :invitations, ShotElixir.Invitations.Invitation
    has_many :schticks, ShotElixir.Schticks.Schtick
    has_many :weapons, ShotElixir.Weapons.Weapon
    has_many :parties, ShotElixir.Parties.Party
    has_many :sites, ShotElixir.Sites.Site
    has_many :factions, ShotElixir.Factions.Faction
    has_many :junctures, ShotElixir.Junctures.Juncture

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [:name, :description, :active, :is_master_template, :user_id])
    |> validate_required([:name, :user_id])
    |> unique_constraint([:name, :user_id])
    |> validate_only_one_master_template()
  end

  defp validate_only_one_master_template(changeset) do
    case get_change(changeset, :is_master_template) do
      true ->
        validate_change(changeset, :is_master_template, fn _, _ ->
          case Repo.exists?(from c in __MODULE__, where: c.is_master_template == true) do
            true -> [is_master_template: "can only be true for one campaign at a time"]
            false -> []
          end
        end)
      _ -> changeset
    end
  end
end