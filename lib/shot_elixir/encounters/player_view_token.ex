defmodule ShotElixir.Encounters.PlayerViewToken do
  @moduledoc """
  Schema for magic link tokens that allow players to access the Player View
  for a specific character in an encounter.

  Tokens are:
  - Single-use (marked as used after redemption)
  - Time-limited (expire after 10 minutes)
  - Tied to a specific character, fight, and user
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @token_expiry_minutes 10

  schema "player_view_tokens" do
    field :token, :string
    field :expires_at, :utc_datetime
    field :used, :boolean, default: false
    field :used_at, :utc_datetime

    belongs_to :fight, ShotElixir.Fights.Fight
    belongs_to :character, ShotElixir.Characters.Character
    belongs_to :user, ShotElixir.Accounts.User

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @doc """
  Generates a cryptographically secure token.
  """
  def generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Returns the default expiry time (10 minutes from now).
  """
  def default_expiry do
    DateTime.utc_now()
    |> DateTime.add(@token_expiry_minutes * 60, :second)
    |> DateTime.truncate(:second)
  end

  @doc """
  Changeset for creating a new player view token.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:token, :expires_at, :used, :used_at, :fight_id, :character_id, :user_id])
    |> validate_required([:token, :expires_at, :fight_id, :character_id, :user_id])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:fight_id)
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for marking a token as used.
  """
  def use_changeset(token) do
    token
    |> change(used: true, used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Checks if a token is valid (not expired and not used).
  """
  def valid?(%__MODULE__{used: true}), do: false

  def valid?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def valid?(_), do: false
end
