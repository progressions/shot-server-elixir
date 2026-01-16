defmodule ShotElixir.Repo.Migrations.AddDiscordUsernameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :discord_username, :string
    end
  end
end
