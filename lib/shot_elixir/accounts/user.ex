defmodule ShotElixir.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.ImagePositions.ImagePosition

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :encrypted_password, :string
    field :password, :string, virtual: true
    field :first_name, :string
    field :last_name, :string
    field :name, :string
    field :active, :boolean, default: true
    field :admin, :boolean, default: false
    field :gamemaster, :boolean, default: true
    field :jti, :string
    field :confirmed_at, :naive_datetime
    field :confirmation_token, :string
    field :confirmation_sent_at, :naive_datetime
    field :unconfirmed_email, :string
    field :reset_password_token, :string
    field :reset_password_sent_at, :naive_datetime
    field :locked_at, :naive_datetime
    field :failed_attempts, :integer, default: 0
    field :unlock_token, :string

    belongs_to :current_campaign, Campaign
    belongs_to :pending_invitation, ShotElixir.Invitations.Invitation

    has_many :campaigns, ShotElixir.Campaigns.Campaign, foreign_key: :user_id
    has_many :characters, ShotElixir.Characters.Character
    has_many :vehicles, ShotElixir.Vehicles.Vehicle
    has_many :campaign_memberships, ShotElixir.Campaigns.CampaignMembership
    has_many :player_campaigns, through: [:campaign_memberships, :campaign]
    has_many :invitations, ShotElixir.Invitations.Invitation
    has_one :onboarding_progress, ShotElixir.Onboarding.Progress

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "User"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :password,
      :first_name,
      :last_name,
      :admin,
      :gamemaster,
      :current_campaign_id,
      :pending_invitation_id
    ])
    |> validate_required([:email, :first_name, :last_name])
    |> validate_format(:email, ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/)
    |> validate_length(:first_name, min: 2)
    |> validate_length(:last_name, min: 2)
    |> validate_length(:password, min: 6, message: "should be at least 6 characters")
    |> unique_constraint(:email, name: :index_users_on_email)
    |> set_name()
    |> hash_password()
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> generate_jti()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :first_name, :last_name, :admin, :gamemaster, :current_campaign_id])
    |> validate_required([:email, :first_name, :last_name])
    |> validate_format(:email, ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/)
    |> validate_length(:first_name, min: 2)
    |> validate_length(:last_name, min: 2)
    |> unique_constraint(:email, name: :index_users_on_email)
    |> set_name()
  end

  defp set_name(changeset) do
    case {get_change(changeset, :first_name), get_change(changeset, :last_name)} do
      {nil, nil} ->
        changeset

      _ ->
        first = get_field(changeset, :first_name) || ""
        last = get_field(changeset, :last_name) || ""
        put_change(changeset, :name, String.trim("#{first} #{last}"))
    end
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :encrypted_password, Bcrypt.hash_pwd_salt(password))
    end
  end

  defp generate_jti(changeset) do
    put_change(changeset, :jti, generate_token())
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64()
  end

  def verify_password(user, password) do
    Bcrypt.verify_pass(password, user.encrypted_password)
  end
end
