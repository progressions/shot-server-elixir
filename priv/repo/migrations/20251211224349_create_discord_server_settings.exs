defmodule ShotElixir.Repo.Migrations.CreateDiscordServerSettings do
  use Ecto.Migration

  def change do
    create table(:discord_server_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Discord server ID (snowflake - 64-bit integer)
      add :server_id, :bigint, null: false

      # Current campaign and fight for the server
      add :current_campaign_id, references(:campaigns, type: :binary_id, on_delete: :nilify_all)
      add :current_fight_id, references(:fights, type: :binary_id, on_delete: :nilify_all)

      # Flexible settings for future extensibility
      add :settings, :map, default: %{}, null: false

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    # One record per Discord server
    create unique_index(:discord_server_settings, [:server_id])

    # Optimize lookups by campaign/fight
    create index(:discord_server_settings, [:current_campaign_id])
    create index(:discord_server_settings, [:current_fight_id])
  end
end
