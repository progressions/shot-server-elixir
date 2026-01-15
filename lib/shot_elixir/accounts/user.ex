defmodule ShotElixir.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Accounts.WebauthnCredential

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
    field :at_a_glance, :boolean, default: false
    field :admin, :boolean, default: false
    field :gamemaster, :boolean, default: false
    field :jti, :string
    field :confirmed_at, :naive_datetime_usec
    field :confirmation_token, :string
    field :confirmation_sent_at, :naive_datetime_usec
    field :unconfirmed_email, :string
    field :reset_password_token, :string
    field :reset_password_sent_at, :naive_datetime_usec
    field :locked_at, :naive_datetime_usec
    field :failed_attempts, :integer, default: 0
    field :unlock_token, :string
    field :discord_id, :integer

    belongs_to :current_campaign, Campaign
    belongs_to :current_character, Character
    belongs_to :pending_invitation, ShotElixir.Invitations.Invitation

    has_many :campaigns, ShotElixir.Campaigns.Campaign, foreign_key: :user_id
    has_many :characters, ShotElixir.Characters.Character
    has_many :vehicles, ShotElixir.Vehicles.Vehicle
    has_many :campaign_memberships, ShotElixir.Campaigns.CampaignMembership
    has_many :player_campaigns, through: [:campaign_memberships, :campaign]
    has_many :invitations, ShotElixir.Invitations.Invitation
    has_one :onboarding_progress, ShotElixir.Onboarding.Progress
    has_many :webauthn_credentials, WebauthnCredential

    has_many :image_positions, ImagePosition,
      foreign_key: :positionable_id,
      where: [positionable_type: "User"]

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :naive_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :password,
      :first_name,
      :last_name,
      :at_a_glance,
      :admin,
      :gamemaster,
      :current_campaign_id,
      :pending_invitation_id
    ])
    |> validate_required([:email, :first_name, :last_name])
    |> validate_format(:email, ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/)
    |> validate_length(:first_name, min: 2)
    |> validate_length(:last_name, min: 2)
    |> validate_password_strength()
    |> unique_constraint(:email, name: :users_email_index)
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

  def confirmation_changeset(user, attrs) do
    user
    |> cast(attrs, [:confirmed_at, :confirmation_token, :confirmation_sent_at])
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :first_name,
      :last_name,
      :at_a_glance,
      :admin,
      :gamemaster,
      :current_campaign_id
    ])
    |> validate_required([:email, :first_name, :last_name])
    |> validate_format(:email, ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/)
    |> validate_length(:first_name, min: 2)
    |> validate_length(:last_name, min: 2)
    |> unique_constraint(:email, name: :users_email_index)
    |> set_name()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password_strength()
    |> hash_password()
  end

  @doc """
  Changeset for linking/unlinking Discord account.
  """
  def discord_changeset(user, attrs) do
    user
    |> cast(attrs, [:discord_id, :current_character_id])
    |> unique_constraint(:discord_id, name: :users_discord_id_index)
    |> foreign_key_constraint(:current_character_id)
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

  defp validate_password_strength(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        cond do
          String.length(password) < 8 ->
            add_error(changeset, :password, "must be at least 8 characters")

          not Regex.match?(~r/[a-zA-Z]/, password) ->
            add_error(changeset, :password, "must contain at least one letter")

          not Regex.match?(~r/[0-9]/, password) ->
            add_error(changeset, :password, "must contain at least one number")

          true ->
            changeset
        end
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
