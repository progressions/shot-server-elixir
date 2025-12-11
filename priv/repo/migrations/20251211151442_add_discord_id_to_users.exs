defmodule ShotElixir.Repo.Migrations.AddDiscordIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Discord IDs are snowflakes (large 64-bit integers)
      add :discord_id, :bigint
    end

    # Ensure one Discord account can only link to one Chi War account
    create unique_index(:users, [:discord_id])
  end
end
