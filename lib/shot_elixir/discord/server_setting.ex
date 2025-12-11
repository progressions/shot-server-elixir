defmodule ShotElixir.Discord.ServerSetting do
  @moduledoc """
  Schema for persisting Discord server settings.

  Each Discord server (guild) can have its own settings, including:
  - Current campaign association
  - Current fight association
  - Flexible settings map for future extensibility
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "discord_server_settings" do
    # Discord server ID (snowflake - 64-bit integer)
    field :server_id, :integer

    # Frequently accessed settings as dedicated columns
    belongs_to :current_campaign, ShotElixir.Campaigns.Campaign
    belongs_to :current_fight, ShotElixir.Fights.Fight

    # Flexible settings for future extensibility
    field :settings, :map, default: %{}

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  @doc false
  def changeset(server_setting, attrs) do
    server_setting
    |> cast(attrs, [:server_id, :current_campaign_id, :current_fight_id, :settings])
    |> validate_required([:server_id])
    |> unique_constraint(:server_id)
  end
end
